# 2026-07-10 告警中心唯一事实源补丁部署回执

## 服务器

`192.168.2.167` / `airiver-sy`

## 部署包

`river-watch-alarm-center-source-realtime15-20260710.zip`

最新 SHA256：

```text
48ed1c2eb3904113b5b0299f9301cc8b69959f2d3aaf30ec7a2e05bfdb82667f
```

## 部署结果

用户在服务器执行：

```bash
cd /home/ai-river/river-watch-alarm-center-source-realtime15-20260710
APP_DIR=/home/ai-river/river-watch bash ./scripts/apply-alarm-center-source-realtime15-20260710.sh
```

脚本输出显示：

```text
== River Watch alarm-center source realtime15 incremental patch ==
APP_DIR=/home/ai-river/river-watch
PKG_DIR=/home/ai-river/river-watch-alarm-center-source-realtime15-20260710
== 1. Backup changed frontend files and dist ==
Backup saved: /home/ai-river/river-watch/backups/alarm-center-source-realtime15-20260710-20260710-185311
== 2. Apply incremental source files ==
== 3. Apply prebuilt frontend dist ==
== 4. Hot update frontend container static assets when present ==
Frontend container: deploy-frontend-1
== 5. Smoke test ==
curl: (56) Recv failure: 连接被对方重置
DONE: alarm center source realtime15 patch applied
```

说明：`curl: (56)` 出现在前端容器刚 restart 后的即时 smoke 阶段，后续验证容器已恢复 healthy，页面可访问。

## 现场验证

源码标记已确认：

```text
/home/ai-river/river-watch/frontend/src/stores/platform.ts:  const rows = activeAlarmRowsForState(state).filter((alarm) => !dispatched.has(alarm.id));
/home/ai-river/river-watch/frontend/src/stores/platform.ts:function activeAlarmRowsForState(state: AlarmFlowState): Alarm[] {
/home/ai-river/river-watch/frontend/src/__tests__/navBadges.test.ts:  it('does not post realtime overflow from the frontend because alarm records are persisted by backend ingest', async () => {
```

前端容器状态：

```text
deploy-frontend-1 Up 23 seconds (healthy) 0.0.0.0:8081->80/tcp
```

页面 smoke：

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
```

## 结论

补丁已经部署到 `/home/ai-river/river-watch`，并已热更新 `deploy-frontend-1` 静态资源。当前规则为：告警中心是唯一事实源，实时异常只显示告警中心 active 告警中的最新 15 条。
