# River Watch 历史标注与研判三列布局增量包

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
sha256sum -c river-watch-alarm-evidence-annotations-layout-increment-20260715.zip.sha256
rm -rf river-watch-alarm-evidence-annotations-layout-increment-20260715
unzip -o river-watch-alarm-evidence-annotations-layout-increment-20260715.zip
cd river-watch-alarm-evidence-annotations-layout-increment-20260715
sha256sum -c SHA256SUMS
bash -n scripts/*.sh
python3 tests/test_package.py
chmod +x scripts/*.sh
sudo -v

LOG="/home/ai-river/alarm-evidence-annotations-layout-apply-$(date +%Y%m%d-%H%M%S).log"
nohup sudo -n env APP_DIR=/home/ai-river/river-watch \
  bash scripts/apply-alarm-evidence-annotations-layout-increment-20260715.sh \
  >"$LOG" 2>&1 &
echo "pid=$!"
echo "log=$LOG"
tail -f "$LOG"
```

## 验收

- 日志结尾必须出现 `VERIFY OK` 和 `DONE`。
- 新告警的研判图片必须显示异常框和文字。
- 旧告警只有在原 `rw_ai_event` 尚存在时才能准确回填；原事件已删除的记录不会伪造标注框。

