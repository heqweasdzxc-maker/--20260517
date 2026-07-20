# Apparent restart during extraction

Date: 2026-07-20

## Evidence

The SSH session ended immediately after the final `unzip` output. None of the following commands ran:

- package `SHA256SUMS` verification;
- `sudo -v`;
- creation of the background deployment PID and log;
- the apply script's first banner;
- Docker or systemd restart operations.

The original ZIP was produced by Windows `Compress-Archive`. Ubuntu `unzip` reported that it used backslashes as path separators. Info-ZIP warnings can return a non-zero status; combined with `set -e`, that status exits the login shell. Xshell then reconnects automatically, which presents like a host restart even though the deployment script never started.

Confirm host state with `uptime -s`, `who -b`, and `last -x reboot`. Confirm the archive behavior without enabling `errexit`:

```bash
set +e
unzip -t /home/ai-river/river-watch-channel-isolation-evidence-db-cleanup-increment-20260720.zip >/tmp/river-unzip-test.log 2>&1
rc=$?
tail -20 /tmp/river-unzip-test.log
echo "unzip_rc=$rc"
```

## Packaging correction

The v2 ZIP is generated with POSIX `/` member paths. Validation found 69 members and zero backslash paths; archive test returned `0`.

- File: `river-watch-channel-isolation-evidence-db-cleanup-increment-20260720-v2.zip`
- SHA-256: `35fc0a669826939a0e0196578790b1cd4e4b279f6307c7a5730d62cd00daf077`

The application payload is unchanged. Only the ZIP container/path encoding was corrected.

