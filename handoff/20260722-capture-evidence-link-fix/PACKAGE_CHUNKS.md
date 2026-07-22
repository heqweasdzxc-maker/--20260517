# Package chunks

The deployment ZIP is stored as 48 ordered Base64 chunks to keep the GitHub handoff reliable.

Rebuild and verify:

```bash
chmod +x rebuild-package.sh
./rebuild-package.sh
```

Expected SHA256: `cdb1eb1fdc78c36380eea2cd9c142e66cf1ae9f5502636affbca58a682508aa7`.
