# River Watch capture and alarm-evidence fix v3

This revision supersedes the initial 2026-07-22 handoff package.

## Changes

- Replaces the screenshot scheduler with one high-resolution image per camera every 30 minutes for 10 days (480 slots).
- Persists the exact AI detection frame instead of reopening RTSP after an alarm.
- Tags every new evidence JPEG with `RIVERWATCH-EVIDENCE-V1|CHxx` and verifies the marker, database camera, payload camera, and alarm camera.
- Returns HTTP 409 and blocks display for mismatched or unverifiable legacy evidence.
- Treats HTTP 409 as terminal in the frontend, so no fallback image can replace rejected evidence.
- Updates only frontend `index.html` and `assets`; unrelated digital-twin and model resources remain untouched.

## Package

Archive: `river-watch-capture-evidence-link-increment-20260722-v3.zip`

SHA-256: `98f646e902de5621c122772ee71cca963535b029a69452c27b8ec7647991fcfb`

Run `rebuild-package.sh` in this directory to reconstruct and verify the ZIP from `package-parts/`.

The deployment script checks exact production baselines, backs up every changed file, restarts only the existing group topology and affected frontend/backend containers, and rolls back automatically on failure.
