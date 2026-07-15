# River Watch 历史标注与研判三列布局增量包 v2

本包已基于 2026-07-15 20:22 从 `192.168.2.167` 导出的实际运行后端重新变基：

- `server.mjs`: `7db1272481c3a6e51797759c22f1cb8574d1c1abed5044b7988baffc6f8182ca`
- `store.mjs`: `5105048363fe6f2fdd0095a6e8a867abe358701b3c3b588c738c284fdb913196`

不会引入未在当前生产后端启用的 integrations、security hardening 或 WVP 同步代码。

## 处理范围

1. 告警证据截图与异常标注元数据一起持久化，不再依赖平台快照最近 100 条 AI 事件。
2. 已有证据可按 `event_id` 回查 `rw_ai_event`，部署时将可找回的标注一次性回填到证据表。
3. 事件态势和告警中心共用的研判对话框都使用历史证据标注。
4. 图片下方 13 个研判字段改为每行三组，小屏自动降为两列或一列。

## 不在本包内

- 不修改 `river-ai-group@*` 或 `river-ai-batch@*` 服务。
- 不替换模型，不改变采样率、置信度和 GPU 调度。
- 不删除告警、AI 事件或证据数据。

## 部署

```bash
cd /home/ai-river
sha256sum -c river-watch-alarm-evidence-annotations-layout-increment-20260715-v2.zip.sha256
rm -rf river-watch-alarm-evidence-annotations-layout-increment-20260715-v2
unzip -o river-watch-alarm-evidence-annotations-layout-increment-20260715-v2.zip
cd river-watch-alarm-evidence-annotations-layout-increment-20260715-v2
sha256sum -c SHA256SUMS
bash -n scripts/*.sh
python3 tests/test_package.py
chmod +x scripts/*.sh
sudo -v

LOG="/home/ai-river/alarm-evidence-annotations-layout-v2-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env APP_DIR=/home/ai-river/river-watch \
  bash scripts/apply-alarm-evidence-annotations-layout-increment-20260715-v2.sh \
  >"$LOG" 2>&1 &
echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

## 验收

- 日志结尾必须出现 `VERIFY OK` 和 `DONE`。
- 新告警的研判图片必须显示异常框和文字。
- 旧告警只有在原 `rw_ai_event` 尚存在时才能准确回填；原事件已删除的记录不会伪造标注框。
