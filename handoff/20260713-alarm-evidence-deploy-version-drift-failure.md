# 2026-07-13 Alarm evidence deployment version-drift failure

## Status

The backend was successfully restored from:

`/home/ai-river/river-watch/backups/alarm-evidence-snapshot-increment-20260712-20260713-100913`

After restoration:

- `deploy-backend-1` returned `UP`
- MySQL and frontend remained running
- The evidence frontend deployment step had not executed
- No evidence schema/data change was committed

## Failure

The first alarm-evidence package copied complete local versions of `server.mjs`, `store.mjs`, and `ai-ingest.mjs` into the running container. The replacement `server.mjs` imports:

`/app/src/integrations/index.mjs`

The actual running container version did not contain that directory, causing an immediate restart loop:

```text
Error [ERR_MODULE_NOT_FOUND]: Cannot find module '/app/src/integrations/index.mjs'
```

## Root cause

The source tree under `/home/ai-river/river-watch/backend/src` and the source baked into/running inside `deploy-backend-1:/app/src` are not the same release. Replacing whole backend files crossed that version boundary and introduced imports unavailable in the running image.

## Required correction

The original package must not be rerun. The next package must be rebased on a fresh export of the actual running container source and use narrowly anchored edits plus a new helper module. It must not replace complete backend files from the local handoff tree.

Superseded package:

- `river-watch-alarm-evidence-snapshot-increment-20260712.zip`
- SHA-256 `2f094a105ea7eff4bab7c761019257f8292cd0c127e836c53c3bbbb857e5e24b`
- Status: DO NOT DEPLOY on the current 192.168.2.167 backend image.
