# 2026-07-10 告警中心最新告警排序热修

## 问题

部署“告警中心唯一事实源 / 实时异常最新15条”补丁后，告警中心列表仍未把最新告警显示在顶部。

## 根因

`frontend/src/views/pages/AlarmsPage.vue` 使用了 `platform.alarmRows`，但页面层又默认按 `alarm.time` 展示字段排序：

```ts
const alarmSort = ref({ prop: 'time', order: 'descending' });
```

`alarm.time` 是展示文本，不一定等于数据库入库时间或更新时间。结果是新入库告警可能因为 `time` 字段较小而排到后面。

## 修复

将告警中心“时间”列默认排序取值改为：

```ts
if (prop === 'time') return alarm.updatedAt || alarm.createdAt || alarm.time;
```

表格显示仍保留 `time` 字段，只改变排序依据。

## 本地改动文件

- `codex-handoff/frontend/src/views/pages/AlarmsPage.vue`
- `codex-handoff/frontend/src/__tests__/alarmsFilterLayout.test.ts`

## 增量包

```text
river-watch-alarm-center-sort-hotfix-20260710.zip
```

SHA256：

```text
bc06148cdfe9ea983fe56689cd6696f33170f7b0c43777f9ec6ec28de45d07e2
```

## 验证

在 `E:\river-video-app-V3.0\codex-handoff\frontend` 执行：

```bash
npm test -- src/__tests__/alarmsFilterLayout.test.ts
npm test
npm run build
```

结果：

- `alarmsFilterLayout.test.ts`: 2 passed
- 全量前端单测：37 files / 145 tests passed
- 前端构建成功
- 构建仅出现第三方 Element Plus/Rolldown pure annotation warning 和 chunk size warning

## 服务器部署命令

```bash
cd /home/ai-river
unzip -o river-watch-alarm-center-sort-hotfix-20260710.zip -d river-watch-alarm-center-sort-hotfix-20260710
cd river-watch-alarm-center-sort-hotfix-20260710
chmod +x scripts/apply-alarm-center-sort-hotfix-20260710.sh
APP_DIR=/home/ai-river/river-watch ./scripts/apply-alarm-center-sort-hotfix-20260710.sh
```

部署后浏览器对 `/alarms` 执行 `Ctrl + F5` 强刷。