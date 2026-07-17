
# River Watch training capture hotfix v2

- Target: `192.168.2.167`
- Package: `river-watch-training-capture-hotfix-20260717-v2.zip`
- Package SHA-256: `a8db640e85b6903c21db682d24db698c2cbe12e5105c80daf7b52862f66ba2c4`
- Deployment state: packaged and independently verified locally; server deployment pending.

## Evidence from the returned archive

The returned archive checksum matched. It contained CH01-CH10 directories but
no JPEG files. `manifest.tsv` proves that slot 0 ran:

- CH01-CH09: `ffmpeg_exit_8`
- CH10: `ffmpeg_exit_143` (known offline camera timeout)

The original tool discarded FFmpeg stderr, so the archive cannot identify the
single underlying FFmpeg message. This is a capture failure, not an export or
packaging omission.

## Changes

- remove duplicate `nice` and `ionice` wrappers from the FFmpeg command;
- preserve low CPU and I/O priority through the existing systemd unit;
- redact credentials and persist a short FFmpeg failure reason;
- try Hikvision main stream, configured original stream and inference stream;
- retry the current slot only when it has zero usable images;
- add an allowlisted server-home cleanup script with dry-run default;
- protect the live app, active captures and database backups from cleanup.

## Verification

- ZIP outer SHA-256 matched.
- All 17 package entries matched `SHA256SUMS` after independent extraction.
- Python unit/package tests: 30 passed.
- Python compilation: passed.
- ShellCheck for every shell script: passed.
- No Python cache files are present in the ZIP.

## Production acceptance still required

After deployment, confirm at least one online channel writes a non-empty JPEG,
its manifest row is `SUCCESS` or `LOW_RESOLUTION`, and no RTSP credentials appear
in the manifest or journal. Do not mark production deployment complete before
this evidence is collected.


