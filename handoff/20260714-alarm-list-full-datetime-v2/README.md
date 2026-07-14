# River Watch Alarm List Full Datetime Increment 20260714 v2

## 修复说明

v1 只携带了新主入口和告警页分块，但新入口引用了同一次构建生成的其他页面分块。服务器原有页面分块哈希与新入口不一致，导致告警页可打开、左侧其他菜单动态加载失败。

v2 保留日期时间功能，并携带本次构建完整的 `frontend/dist/assets` 依赖闭包。它不会携带或覆盖 `digital-twin`、视频、地图离线资源、后端、数据库和 AI 推理文件。

## 变更内容

- 告警中心显示 `YYYY-MM-DD HH:mm:ss`，时区为 `Asia/Shanghai`。
- 默认排序继续使用持久化时间，最新告警在最上方。
- 部署前验证所有入口和动态页面分块均已包含在包内。
- 完整备份现有前端源码、宿主机 assets 和前端容器 assets。
- 失败时自动回滚，只保留最近 3 份同类备份。

## 部署范围

- 更新：`frontend/src/views/pages/AlarmsPage.vue`
- 新增：`frontend/src/utils/alarmDateTime.ts`
- 更新相关前端测试。
- 更新：`frontend/dist/index.html` 和 `frontend/dist/assets`。
- 仅重启：`deploy-frontend-1`。

## 验证

```bash
node scripts/verify-frontend-dist-closure.mjs frontend/dist
```

该检查会从 `index.html` 追踪入口、动态导入和样式依赖，任何缺失文件都会返回非零状态。
