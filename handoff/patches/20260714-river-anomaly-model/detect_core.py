"""纯逻辑检测核心：类别映射 / 水色异常 / 水位估计 / 元数据 payload。

只依赖 numpy，便于单测（不引入 cv2 / onnxruntime）。
worker 负责拉流、解码、跑 YOLO ONNX，再调用本模块完成「映射 + 颜色/水位基线 + 组装回传体」。
"""

from __future__ import annotations

import time
import uuid
from typing import Optional

import numpy as np

# 系统中文事件词表（须与前端异常框 / db schema 一致）
CAT_FLOATING_CLUSTER = "漂浮物聚集"
CAT_FLOATING = "漂浮物"
CAT_PLANKTON = "浮游物"
CAT_COLOR = "水色异常"
CAT_LEVEL = "水位异常"
CAT_PERSON_WATER = "人员落水"
CAT_DUMPING = "非法倾倒"
CAT_CRACK = "墙体裂痕"
CAT_SEEPAGE = "污水渗漏"
CAT_STAIN = "地面水渍"

# 检测模型原始类名 → 系统中文类别
CATEGORY_MAP = {
    "willow_fluff": CAT_FLOATING,
    "leaf": CAT_FLOATING,
    "trash": CAT_FLOATING,
    "garbage": CAT_FLOATING,
    "bottle": CAT_FLOATING,
    "plastic": CAT_FLOATING,
    "plastic_bottle": CAT_FLOATING,
    "debris": CAT_FLOATING,
    "floating_debris": CAT_FLOATING,
    "other_debris": CAT_FLOATING,
    "daily_item": CAT_FLOATING,
    "slipper": CAT_FLOATING,
    "foam": CAT_FLOATING_CLUSTER,
    "algae": CAT_PLANKTON,
    "plankton": CAT_PLANKTON,
    "waterweed": CAT_PLANKTON,
    "water_grass": CAT_PLANKTON,
    "aquatic_weed": CAT_PLANKTON,
    "water_discoloration": CAT_COLOR,
    "garbage_bag": CAT_FLOATING,
    "plastic_foam": CAT_FLOATING_CLUSTER,
    "water_foam": CAT_FLOATING_CLUSTER,
    # 水鸟是正常环境目标。模型保留该类用于消歧，但不得生成异常告警。
    "water_bird": None,
    # 人员落水（河道场景安全类，最高优先级）
    "person": CAT_PERSON_WATER,
    "person_in_water": CAT_PERSON_WATER,
    "drowning": CAT_PERSON_WATER,
    # 非法倾倒
    "dumping": CAT_DUMPING,
    "illegal_dumping": CAT_DUMPING,
    # 结构缺陷场景（墙体裂痕 / 地面水渍）
    "crack": CAT_CRACK,
    "wall_crack": CAT_CRACK,
    "wall_crack_leak": CAT_CRACK,
    "fissure": CAT_CRACK,
    # 污水渗漏：墙面/接缝湿痕渗流，独立类别
    "seepage": CAT_SEEPAGE,
    "leak": CAT_SEEPAGE,
    "leakage": CAT_SEEPAGE,
    "wet_seepage": CAT_SEEPAGE,
    # 地面水渍：地面无定形积水/水渍
    "stain": CAT_STAIN,
    "water_stain": CAT_STAIN,
    "damp": CAT_STAIN,
}


# COCO 80 类标准名录（与官方索引一致），用于通用预训练权重冷启动
COCO80_NAMES = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush",
]

# COCO 类别中与河道场景相关的补充映射（其余 COCO 类在严格模式下丢弃）
CATEGORY_MAP.update({
    "backpack": CAT_FLOATING,
    "umbrella": CAT_FLOATING,
    "handbag": CAT_FLOATING,
    "suitcase": CAT_FLOATING,
    "sports ball": CAT_FLOATING,
    "cup": CAT_FLOATING,
    "bowl": CAT_FLOATING,
})


def map_class(raw_label: str) -> Optional[str]:
    """映射检测类别；显式忽略类返回 None，其他未知类按通用漂浮物处理。"""
    key = str(raw_label).strip().lower()
    return CATEGORY_MAP.get(key, CAT_FLOATING)


def map_class_strict(raw_label: str):
    """严格映射：未登记类别返回 None（COCO 等通用权重用，避免 dog/car 误报成漂浮物）。"""
    key = str(raw_label).strip().lower()
    return CATEGORY_MAP.get(key)


def make_box(cls: str, score: float, x: float, y: float, w: float, h: float) -> dict:
    """归一化坐标的检测框（与后端 boxes 契约一致）。"""
    clamp = lambda v: float(max(0.0, min(1.0, v)))
    return {
        "cls": cls,
        "score": round(float(max(0.0, min(1.0, score))), 4),
        "x": clamp(x),
        "y": clamp(y),
        "w": clamp(w),
        "h": clamp(h),
    }


def build_payload(camera_id: str, pts: float, boxes: list[dict], event_id: Optional[str] = None) -> dict:
    """组装 POST /api/v1/alarms/metadata 的请求体。"""
    return {
        "eventId": event_id or f"AI-{int(time.time() * 1000)}-{uuid.uuid4().hex[:8]}",
        "cameraId": camera_id,
        "pts": float(pts),
        "boxes": list(boxes),
    }


# ---------------- 颜色空间 ----------------

def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    """向量化 RGB(0-255) → HSV，H∈[0,360) S,V∈[0,1]。输入 (H,W,3)。"""
    arr = rgb.astype(np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = np.max(arr, axis=-1)
    mn = np.min(arr, axis=-1)
    diff = mx - mn

    hue = np.zeros_like(mx)
    mask = diff > 1e-6
    # 红为最大
    rmask = mask & (mx == r)
    hue[rmask] = (60 * ((g - b) / np.where(diff == 0, 1, diff)) % 360)[rmask]
    gmask = mask & (mx == g)
    hue[gmask] = (60 * ((b - r) / np.where(diff == 0, 1, diff)) + 120)[gmask]
    bmask = mask & (mx == b)
    hue[bmask] = (60 * ((r - g) / np.where(diff == 0, 1, diff)) + 240)[bmask]
    hue = hue % 360

    sat = np.where(mx <= 1e-6, 0.0, diff / np.where(mx == 0, 1, mx))
    val = mx
    return np.stack([hue, sat, val], axis=-1)


def _roi_slice(shape: tuple, roi: Optional[tuple]):
    """roi = (x,y,w,h) 归一化；返回 numpy 切片 (rows, cols) 与归一化偏移。"""
    h, w = shape[0], shape[1]
    if not roi:
        return (slice(0, h), slice(0, w)), (0.0, 0.0, 1.0, 1.0)
    rx, ry, rw, rh = roi
    x0, y0 = int(rx * w), int(ry * h)
    x1, y1 = int(min(1.0, rx + rw) * w), int(min(1.0, ry + rh) * h)
    x0, x1 = max(0, x0), max(x0 + 1, x1)
    y0, y1 = max(0, y0), max(y0 + 1, y1)
    return (slice(y0, y1), slice(x0, x1)), (x0 / w, y0 / h, (x1 - x0) / w, (y1 - y0) / h)


def analyze_water_color(
    rgb: np.ndarray,
    baseline: Optional[dict] = None,
    roi: Optional[tuple] = None,
    sat_thresh: float = 0.45,
    dark_val: float = 0.22,
) -> Optional[dict]:
    """水色异常基线检测：在 ROI 内统计 HSV，判定发绿(藻)/发黑/泛白。

    baseline: {'hue':..,'sat':..,'val':..} 该点位正常水色；缺省用经验阈值。
    返回检测框 dict 或 None。
    """
    (rows, cols), (bx, by, bw, bh) = _roi_slice(rgb.shape, roi)
    region = rgb[rows, cols]
    if region.size == 0:
        return None
    hsv = rgb_to_hsv(region)
    mean_h = float(np.mean(hsv[..., 0]))
    mean_s = float(np.mean(hsv[..., 1]))
    mean_v = float(np.mean(hsv[..., 2]))

    score = 0.0
    reason = ""
    # 发绿（藻类爆发）：色相落在绿区且饱和度偏高
    if 70 <= mean_h <= 160 and mean_s >= sat_thresh:
        score = max(score, 0.70 + min(0.25, (mean_s - sat_thresh)))
        reason = "偏绿/藻类"
    # 发黑（黑臭水体）：明度过低
    if mean_v <= dark_val:
        score = max(score, 0.72 + min(0.2, (dark_val - mean_v) * 2))
        reason = "发黑"
    # 泛白/浑浊：低饱和高明度
    if mean_s <= 0.12 and mean_v >= 0.75:
        score = max(score, 0.70)
        reason = "泛白/浑浊"

    if baseline:
        dh = min(abs(mean_h - baseline.get("hue", mean_h)), 360 - abs(mean_h - baseline.get("hue", mean_h)))
        ds = abs(mean_s - baseline.get("sat", mean_s))
        dv = abs(mean_v - baseline.get("val", mean_v))
        dev = dh / 180 + ds + dv
        if dev >= 0.35:
            score = max(score, min(0.95, 0.65 + dev / 2))
            reason = reason or "偏离基线"

    if score <= 0:
        return None
    return make_box(CAT_COLOR, score, bx, by, bw, bh)


def estimate_waterline(rgb: np.ndarray, roi: Optional[tuple] = None) -> float:
    """在 ROI 内按行亮度梯度估计水陆分界行，返回归一化行位置 [0,1]（整图坐标）。"""
    (rows, cols), (bx, by, bw, bh) = _roi_slice(rgb.shape, roi)
    region = rgb[rows, cols].astype(np.float32)
    if region.shape[0] < 3:
        return by + bh / 2
    row_mean = region.mean(axis=(1, 2))  # 每行平均亮度
    grad = np.abs(np.diff(row_mean))
    edge = int(np.argmax(grad))  # ROI 内分界行
    return by + (edge / region.shape[0]) * bh


def waterline_anomaly(
    rgb: np.ndarray,
    ref_row: float,
    tol: float = 0.06,
    roi: Optional[tuple] = None,
) -> Optional[dict]:
    """水位异常：当前水线相对参考行偏移超过 tol 即告警。ref_row/tol 为归一化。"""
    line = estimate_waterline(rgb, roi)
    delta = line - ref_row
    if abs(delta) < tol:
        return None
    score = min(0.95, 0.7 + (abs(delta) - tol) * 2)
    (rows, cols), (bx, by, bw, bh) = _roi_slice(rgb.shape, roi)
    band_y = max(0.0, min(line, ref_row) - 0.02)
    band_h = abs(delta) + 0.04
    return make_box(CAT_LEVEL, score, bx, band_y, bw, band_h)
