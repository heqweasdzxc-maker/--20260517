#!/usr/bin/env python3
"""Capture high-resolution training frames without touching River Watch services."""

from __future__ import annotations

import re
import argparse
import os
import shutil
import subprocess
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


STREAM_KEYS = (
    "TRAINING_CAPTURE_URL",
    "HIGHRES_RTSP_URL",
    "RTSP_URL",
    "INFERENCE_STREAM_URL",
)


@dataclass(frozen=True)
class CaptureResult:
    status: str
    width: int = 0
    height: int = 0
    byte_size: int = 0
    relative_path: str = ""
    reason: str = ""


@dataclass(frozen=True)
class RunConfig:
    run_id: str
    start_epoch: int
    end_epoch: int
    output_root: Path
    run_dir: Path
    env_dir: Path
    max_slots: int = 480
    interval_sec: int = 1800
    max_bytes: int = 5 * 1024**3
    min_free_bytes: int = 5 * 1024**3
    owner: str = "ai-river"
    group: str = "ai-river"


def parse_env_file(path: str | Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def select_stream_url(values: dict[str, str]) -> str:
    candidates = stream_candidates(values)
    return candidates[0] if candidates else ""


def stream_candidates(values: dict[str, str]) -> list[str]:
    candidates: list[str] = []
    for key in STREAM_KEYS:
        selected = str(values.get(key, "")).strip()
        if not selected:
            continue
        high_resolution = re.sub(
            r"(?i)(/Streaming/Channels/)102(?=\Z|[/?#])",
            r"\g<1>101",
            selected,
            count=1,
        )
        for candidate in (high_resolution, selected):
            if candidate and candidate not in candidates:
                candidates.append(candidate)
    return candidates


def _stderr_reason(completed: subprocess.CompletedProcess, limit: int = 120) -> str:
    detail = safe_error(getattr(completed, "stderr", ""), limit=limit)
    return "" if detail == "unknown_error" else detail


def slot_for(start_epoch: int | float, now_epoch: int | float, interval_sec: int = 1800) -> int:
    elapsed = float(now_epoch) - float(start_epoch)
    if elapsed < 0:
        raise ValueError("current time is before run start")
    if interval_sec <= 0:
        raise ValueError("interval must be positive")
    return int(elapsed // interval_sec)


def safe_error(reason: object, limit: int = 160) -> str:
    text = str(reason or "unknown_error")
    text = re.sub(r"(?i)([a-z][a-z0-9+.-]*://)[^/@\s]+@", r"\1***@", text)
    text = " ".join(text.split())
    return text[: max(1, int(limit))]


def capture_camera(
    camera_id: str,
    stream_url: str,
    output_dir: str | Path,
    timestamp: str,
    *,
    command_runner: Callable = subprocess.run,
    timeout_sec: int = 25,
) -> CaptureResult:
    root = Path(output_dir)
    channel_dir = root / camera_id
    channel_dir.mkdir(parents=True, exist_ok=True)
    final_path = channel_dir / f"{camera_id}_{timestamp}.jpg"
    part_path = final_path.with_name(final_path.stem + ".part" + final_path.suffix)
    part_path.unlink(missing_ok=True)

    # This server's FFmpeg build rejects -rw_timeout. The subprocess timeout
    # below bounds stalled RTSP reads without relying on build-specific flags.
    input_args = ["-rtsp_transport", "tcp"] if stream_url.lower().startswith("rtsp://") else []
    command = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        *input_args,
        "-i",
        stream_url,
        "-map",
        "0:v:0",
        "-frames:v",
        "1",
        "-q:v",
        "2",
        "-vcodec",
        "mjpeg",
        "-f",
        "image2",
        str(part_path),
    ]

    try:
        completed = command_runner(
            command,
            capture_output=True,
            text=True,
            timeout=max(1, int(timeout_sec)),
            check=False,
        )
    except subprocess.TimeoutExpired:
        part_path.unlink(missing_ok=True)
        return CaptureResult("FAILED", reason="ffmpeg_timeout")
    except OSError:
        part_path.unlink(missing_ok=True)
        return CaptureResult("FAILED", reason="ffmpeg_start_failed")

    if completed.returncode != 0:
        part_path.unlink(missing_ok=True)
        detail = _stderr_reason(completed)
        suffix = f":{detail}" if detail else ""
        return CaptureResult("FAILED", reason=f"ffmpeg_exit_{completed.returncode}{suffix}")
    if not _valid_jpeg(part_path):
        part_path.unlink(missing_ok=True)
        return CaptureResult("INVALID_IMAGE", reason="invalid_jpeg")

    probe_command = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "csv=s=x:p=0",
        str(part_path),
    ]
    try:
        probed = command_runner(
            probe_command,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if probed.returncode != 0:
            raise ValueError("probe failed")
        width_text, height_text = probed.stdout.strip().split("x", 1)
        width, height = int(width_text), int(height_text)
        if width <= 0 or height <= 0:
            raise ValueError("invalid dimensions")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        part_path.unlink(missing_ok=True)
        return CaptureResult("PROBE_FAILED", reason="ffprobe_failed")

    part_path.replace(final_path)
    relative_path = final_path.relative_to(root).as_posix()
    status = "SUCCESS" if width >= 1280 and height >= 720 else "LOW_RESOLUTION"
    return CaptureResult(
        status,
        width=width,
        height=height,
        byte_size=final_path.stat().st_size,
        relative_path=relative_path,
    )


def _valid_jpeg(path: Path) -> bool:
    try:
        if path.stat().st_size < 4:
            return False
        with path.open("rb") as handle:
            start = handle.read(2)
            handle.seek(-2, 2)
            end = handle.read(2)
        return start == b"\xff\xd8" and end == b"\xff\xd9"
    except OSError:
        return False


def load_run_config(path: str | Path) -> RunConfig:
    values = parse_env_file(path)
    required = ("RUN_ID", "START_EPOCH", "END_EPOCH", "OUTPUT_ROOT", "RUN_DIR", "ENV_DIR")
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise ValueError(f"missing run config keys: {','.join(missing)}")
    return RunConfig(
        run_id=values["RUN_ID"],
        start_epoch=int(values["START_EPOCH"]),
        end_epoch=int(values["END_EPOCH"]),
        output_root=Path(values["OUTPUT_ROOT"]),
        run_dir=Path(values["RUN_DIR"]),
        env_dir=Path(values["ENV_DIR"]),
        max_slots=int(values.get("MAX_SLOTS", "480")),
        interval_sec=int(values.get("INTERVAL_SEC", "1800")),
        max_bytes=int(values.get("MAX_BYTES", str(5 * 1024**3))),
        min_free_bytes=int(values.get("MIN_FREE_BYTES", str(5 * 1024**3))),
        owner=values.get("OWNER", "ai-river"),
        group=values.get("GROUP", "ai-river"),
    )


def run_capture(
    config_path: str | Path,
    *,
    now_epoch: int | float | None = None,
    capture_fn: Callable = capture_camera,
    command_runner: Callable = subprocess.run,
    disk_usage_fn: Callable = shutil.disk_usage,
    systemctl_runner: Callable = subprocess.run,
    lock_path: str | Path | None = None,
) -> int:
    config = load_run_config(config_path)
    now = int(time.time() if now_epoch is None else now_epoch)
    config.output_root.mkdir(parents=True, exist_ok=True)
    config.run_dir.mkdir(parents=True, exist_ok=True)
    lock_file = Path(lock_path) if lock_path else config.output_root / ".capture.lock"

    with _exclusive_lock(lock_file):
        _copy_run_config(config_path, config.run_dir / "run.conf")
        slot = slot_for(config.start_epoch, now, config.interval_sec)
        if now >= config.end_epoch or slot >= config.max_slots:
            _write_marker(config.run_dir / "COMPLETE.txt", f"completed_at={_iso_time(now)}\nslots={config.max_slots}\n")
            _disable_timer(systemctl_runner)
            _apply_owner(config, config.run_dir / "COMPLETE.txt")
            return 0

        last_slot_path = config.run_dir / ".last-slot"
        if last_slot_path.exists():
            try:
                if int(last_slot_path.read_text(encoding="ascii").strip()) >= slot:
                    return 0
            except ValueError:
                pass

        if _directory_size(config.run_dir) >= config.max_bytes:
            _stop_for_storage(config, now, "output_limit_reached", systemctl_runner)
            return 0
        if int(disk_usage_fn(config.output_root).free) < config.min_free_bytes:
            _stop_for_storage(config, now, "minimum_free_space_reached", systemctl_runner)
            return 0

        manifest_path = config.run_dir / "manifest.tsv"
        _ensure_manifest(manifest_path)
        timestamp = time.strftime("%Y%m%d_%H%M%S", time.localtime(now))
        stopped_for_storage = False

        for camera_number in range(1, 11):
            camera_id = f"CH{camera_number:02d}"
            env_path = config.env_dir / f"ai-worker-{camera_id}.env"
            if not env_path.is_file():
                continue
            values = parse_env_file(env_path)
            candidates = stream_candidates(values)
            if not candidates:
                result = CaptureResult("NO_STREAM_URL", reason="no_capture_stream_configured")
            else:
                failures: list[str] = []
                result = CaptureResult("FAILED", reason="all_stream_candidates_failed")
                for stream_url in candidates:
                    try:
                        attempt = capture_fn(
                            camera_id,
                            stream_url,
                            config.run_dir,
                            timestamp,
                            command_runner=command_runner,
                        )
                    except Exception as exc:
                        attempt = CaptureResult("FAILED", reason=safe_error(type(exc).__name__))
                    if attempt.status in {"SUCCESS", "LOW_RESOLUTION"}:
                        result = attempt
                        break
                    failures.append(attempt.reason or attempt.status)
                else:
                    result = CaptureResult(
                        "FAILED",
                        reason=safe_error(" | ".join(failures) or "all_stream_candidates_failed"),
                    )

            _append_manifest(manifest_path, slot, camera_id, now, result)
            if result.relative_path:
                _apply_owner(config, config.run_dir / result.relative_path)
            if _directory_size(config.run_dir) >= config.max_bytes:
                _stop_for_storage(config, now, "output_limit_reached", systemctl_runner)
                stopped_for_storage = True
                break
            if int(disk_usage_fn(config.output_root).free) < config.min_free_bytes:
                _stop_for_storage(config, now, "minimum_free_space_reached", systemctl_runner)
                stopped_for_storage = True
                break

        _atomic_write(last_slot_path, f"{slot}\n", encoding="ascii")
        _apply_owner(config, manifest_path)
        _apply_owner(config, last_slot_path)
        return 0 if not stopped_for_storage else 0


def _ensure_manifest(path: Path) -> None:
    if path.exists():
        return
    path.write_text(
        "slot\tcamera_id\tcaptured_at\tstatus\twidth\theight\tbyte_size\tpath\treason\n",
        encoding="utf-8",
    )


def _append_manifest(path: Path, slot: int, camera_id: str, now: int, result: CaptureResult) -> None:
    fields = (
        str(slot),
        camera_id,
        _iso_time(now),
        result.status,
        str(result.width or ""),
        str(result.height or ""),
        str(result.byte_size or ""),
        result.relative_path,
        safe_error(result.reason),
    )
    with path.open("a", encoding="utf-8", newline="") as handle:
        handle.write("\t".join(fields) + "\n")


def _directory_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        try:
            if item.is_file():
                total += item.stat().st_size
        except OSError:
            continue
    return total


def _stop_for_storage(config: RunConfig, now: int, reason: str, systemctl_runner: Callable) -> None:
    marker = config.run_dir / "STOPPED_STORAGE.txt"
    _write_marker(marker, f"stopped_at={_iso_time(now)}\nreason={reason}\n")
    _apply_owner(config, marker)
    _disable_timer(systemctl_runner)


def _disable_timer(systemctl_runner: Callable) -> None:
    try:
        systemctl_runner(
            ["systemctl", "--no-block", "disable", "--now", "river-training-capture.timer"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def _copy_run_config(source: str | Path, target: Path) -> None:
    if target.exists():
        return
    target.write_text(Path(source).read_text(encoding="utf-8"), encoding="utf-8")


def _write_marker(path: Path, content: str) -> None:
    if not path.exists():
        _atomic_write(path, content)


def _atomic_write(path: Path, content: str, *, encoding: str = "utf-8") -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding=encoding)
    temporary.replace(path)


def _iso_time(epoch: int | float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(epoch))


def _apply_owner(config: RunConfig, path: Path) -> None:
    if os.name != "posix" or os.geteuid() != 0 or not config.owner or not config.group:
        return
    try:
        import grp
        import pwd

        os.chown(path, pwd.getpwnam(config.owner).pw_uid, grp.getgrnam(config.group).gr_gid)
    except (KeyError, OSError):
        pass


@contextmanager
def _exclusive_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+b")
    try:
        if os.name == "nt":
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        if os.name == "nt":
            import msvcrt

            handle.seek(0)
            try:
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="/etc/river-watch/training-capture.conf")
    args = parser.parse_args()
    return run_capture(args.config)


if __name__ == "__main__":
    raise SystemExit(main())
