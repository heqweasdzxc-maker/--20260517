# Package reconstruction

The GitHub connector cannot upload a binary ZIP directly. The exact verified deployment ZIP is therefore stored as ordered Base64 chunks.

Run from this directory on Linux:

```bash
chmod +x rebuild-package.sh
./rebuild-package.sh
```

Expected SHA-256:

```text
73cb86f6016a2eba899b88699f1ea9aaf2f5323873393f34f95294627fad506d
```

The reconstructed ZIP is byte-for-byte identical to the local deliverable.

