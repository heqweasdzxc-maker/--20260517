# River Watch training capture FFmpeg compatibility hotfix v3

- Target: `192.168.2.167`
- Package: `river-watch-training-capture-hotfix-20260717-v3.zip`
- Package SHA-256: `692f46c8feb947ee664b3827e5a28d592def4502ca3a44ef98820841dd658772`
- Deployment state: packaged and independently verified locally; server deployment pending.

## Confirmed production root cause

The v2 diagnostic manifest captured the exact FFmpeg error for CH01-CH09:

`Option rw_timeout not found.`

The FFmpeg process rejected the input option before opening each RTSP stream.
CH10 separately reports `No route to host` for the known failed camera at
`192.168.2.21`.

## Minimal change

The v3 package removes only the unsupported `-rw_timeout` argument. RTSP TCP,
the Python 25-second subprocess timeout, stream fallback, redacted diagnostics,
the existing timer and current run directory are retained. No River Watch,
group inference, database, model or camera configuration service is changed.

## Verification

- red test reproduced the unsupported option in the generated command;
- green test removed it while retaining RTSP TCP and subprocess timeout;
- independent ZIP extraction and all 7 internal checksums passed;
- 26 Python tests passed;
- Python compilation passed;
- ShellCheck passed for all deployment scripts.
