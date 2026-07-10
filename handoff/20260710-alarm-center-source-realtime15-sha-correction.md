# 2026-07-10 实时异常最新15条补丁 SHA 修正

上一条记录：`handoff/20260710-alarm-center-source-realtime15.md`

## 修正原因

本地二次检查发现增量包中的 Linux shell 应用脚本由 Windows 写出时带 UTF-8 BOM，直接在服务器执行可能导致 shebang 识别异常。

已修复：`scripts/apply-alarm-center-source-realtime15-20260710.sh` 改为 UTF-8 无 BOM，并保持 LF 换行。

脚本前 4 字节已验证为：

```text
23 21 2F 75
```

即 `#!/u`，无 BOM。

## 最新可用包

增量包名称不变：

```text
river-watch-alarm-center-source-realtime15-20260710.zip
```

最新 SHA256：

```text
48ed1c2eb3904113b5b0299f9301cc8b69959f2d3aaf30ec7a2e05bfdb82667f  river-watch-alarm-center-source-realtime15-20260710.zip
```

请以后续此 SHA 为准，上一条记录里的旧 SHA 作废。

## 验证仍然有效

本次只修正脚本编码并重打包，业务代码和构建产物未变。此前验证结果仍然有效：

- `npm test -- src/__tests__/navBadges.test.ts`: 6 passed
- `npm test`: 37 files / 144 tests passed
- `npm run build`: success
