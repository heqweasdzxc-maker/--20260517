# Incremental Package Policy 2026-07-07

## User Requirement

For any future modification or overwrite operation, only provide an incremental package. Avoid broad cumulative overwrite packages unless explicitly requested.

Key rule from user:

```text
如果要修改覆盖，只改增量包即可，另外需要注意不能影响其他功能
```

## Delivery Rules Going Forward

1. Only include files that are required for the current fix.
2. Do not include unrelated source files, static assets, or full frontend `dist` unless the changed source requires rebuilding static output for deployment.
3. If frontend source changes require static deployment, include only the newly built frontend output needed by the running container and clearly state why it is included.
4. Every package must include:
   - changed file list
   - exact purpose
   - backup path used by apply script
   - SHA256
   - verification commands and results
   - rollback instructions or backup location
5. Apply scripts must backup before overwrite and use permission-safe copy commands such as `sudo install` only for changed files.
6. Do not touch unrelated backend, database, AI worker, stream relay, digital twin, storage, user, report, evidence, work-order, or menu logic when the request is frontend-only.
7. Tests must focus on the changed behavior and must not loosen existing assertions.
8. Full regression verification should still be run locally before packaging.
9. Every modification and deployment receipt must be recorded to GitHub.

## Latest Receipt Context

The `river-watch-realtime-overflow-hotfix-20260707.zip` package was applied successfully on `192.168.2.167`.

Confirmed from receipt:

```text
02017b637bc0cce2d6ebc6d297efb3685ee6b0ff6b2c1206258a881b8f7de869  river-watch-realtime-overflow-hotfix-20260707.zip
Realtime overflow hotfix applied.
deploy-frontend-1     Up 3 minutes (healthy)
frontend-ok
```

The later snapshot check returned:

```text
curl: (22) The requested URL returned error: 401
```

Interpretation: `/api/platform/snapshot` requires authentication/token. This is not a container health failure.

## Recommended Authenticated Snapshot Check

Use a browser-authenticated session or obtain a token through the login API before calling protected APIs. Example shape, adjust username/password to the deployed credentials:

```bash
TOKEN="$({ curl -fsS -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"123456"}' || true; } | python3 -c 'import json,sys; print((json.load(sys.stdin).get("data") or {}).get("token", ""))')"

curl -fsS http://127.0.0.1:8080/api/platform/snapshot \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -120
```

If token acquisition fails, use the actual deployed account or inspect the frontend request headers from an authenticated browser session.
