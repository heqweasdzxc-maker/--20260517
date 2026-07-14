"""detect_core 单测（numpy-only，可直接 python 运行或 pytest）。"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "workers"))
import detect_core as core


def test_map_class():
    assert core.map_class("trash") == core.CAT_FLOATING
    assert core.map_class("ALGAE") == core.CAT_PLANKTON
    assert core.map_class("foam") == core.CAT_FLOATING_CLUSTER
    assert core.map_class("unknown-thing") == core.CAT_FLOATING  # 兜底


def test_second_training_class_mapping():
    assert core.map_class("aquatic_weed") == core.CAT_PLANKTON
    assert core.map_class("garbage_bag") == core.CAT_FLOATING
    assert core.map_class("plastic_foam") == core.CAT_FLOATING_CLUSTER
    assert core.map_class("water_foam") == core.CAT_FLOATING_CLUSTER
    assert core.map_class("water_bird") is None


def test_rgb_to_hsv_primaries():
    px = np.array([[[255, 0, 0], [0, 255, 0], [0, 0, 255]]], dtype=np.uint8)
    hsv = core.rgb_to_hsv(px)
    assert abs(hsv[0, 0, 0] - 0) < 1 or abs(hsv[0, 0, 0] - 360) < 1   # 红 H≈0
    assert abs(hsv[0, 1, 0] - 120) < 1                                # 绿 H≈120
    assert abs(hsv[0, 2, 0] - 240) < 1                                # 蓝 H≈240
    assert np.allclose(hsv[..., 1], 1.0, atol=1e-3)                   # 纯色饱和度=1


def test_water_color_green_anomaly():
    green = np.zeros((100, 100, 3), dtype=np.uint8)
    green[:] = (40, 160, 70)  # 偏绿、较饱和
    box = core.analyze_water_color(green)
    assert box is not None
    assert box["cls"] == core.CAT_COLOR
    assert box["score"] >= 0.7


def test_water_color_normal_blue_no_alarm():
    blue = np.zeros((100, 100, 3), dtype=np.uint8)
    blue[:] = (60, 90, 120)  # 正常偏蓝灰水色
    assert core.analyze_water_color(blue) is None


def test_water_color_dark_anomaly():
    dark = np.full((50, 50, 3), 20, dtype=np.uint8)  # 发黑
    box = core.analyze_water_color(dark)
    assert box is not None and box["cls"] == core.CAT_COLOR


def test_waterline_and_anomaly():
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    img[:30] = 200   # 上方亮（岸）
    img[30:] = 40    # 下方暗（水）→ 分界在 0.3
    line = core.estimate_waterline(img)
    assert 0.25 <= line <= 0.35
    # 参考行 0.55，实际 0.30，偏移 0.25 > tol → 告警
    box = core.waterline_anomaly(img, ref_row=0.55, tol=0.06)
    assert box is not None and box["cls"] == core.CAT_LEVEL
    # 参考行贴近实际 → 不告警
    assert core.waterline_anomaly(img, ref_row=0.30, tol=0.06) is None


def test_build_payload_shape():
    box = core.make_box(core.CAT_COLOR, 0.9, 0.1, 0.2, 0.3, 0.4)
    p = core.build_payload("CH03", 12345.6, [box], event_id="E-1")
    assert p["cameraId"] == "CH03"
    assert p["eventId"] == "E-1"
    assert p["boxes"][0]["cls"] == core.CAT_COLOR
    assert 0 <= p["boxes"][0]["x"] <= 1


def test_make_box_clamps():
    box = core.make_box(core.CAT_LEVEL, 1.5, -0.2, 0.5, 2.0, 0.3)
    assert box["score"] == 1.0
    assert box["x"] == 0.0
    assert box["w"] == 1.0


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"ok  {fn.__name__}")
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
    print(f"\n{len(fns) - failed}/{len(fns)} passed")
    sys.exit(1 if failed else 0)
