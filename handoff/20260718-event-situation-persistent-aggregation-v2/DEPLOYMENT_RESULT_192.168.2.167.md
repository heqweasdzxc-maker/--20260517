# 192.168.2.167 部署回执

- 部署时间：2026-07-18 19:04-19:05（Asia/Shanghai）
- 增量包：`river-watch-event-situation-persistent-aggregation-increment-20260718-v2.zip`
- 包 SHA-256：`64fbc41d111ede77b8fe9f8c5a09d678714ec45b2c89a273a17d0af4fda8e689`
- 应用日志：`/home/ai-river/event-situation-v2-apply-20260718-190448.log`
- 回滚备份：`/home/ai-river/river-watch/backups/event-situation-persistent-aggregation-20260718-v2-20260718-190448`

## 部署结果

- 包内校验和及 6 项包契约测试通过。
- 生产基线哈希全部匹配。
- 容器暂存模块图导入通过：`container module import OK`。
- 线上模块图导入通过：`live module import OK`。
- 后端与前端均在第 2 次轮询恢复就绪。
- 部署脚本以 `VERIFY OK`、`DONE` 正常结束，未触发自动回滚。
- 独立复核脚本以 `VERIFY OK` 正常结束。
- `deploy-backend-1`、`deploy-frontend-1`、`deploy-mysql-1` 正常运行，后端健康接口返回 `UP`。

## 数据结果

- 开放归集事件：32 条。
- 已关联原始告警：1431 条（部署后仍在持续增长）。
- 归集发生次数：47990 次，包含历史告警原有的 `dedupeCount`，不等同于原始告警表行数。
- 最新事件已包含设备、异常类型、首次发生、最近报警、累计次数和状态。

## 说明

- 回执文本中的中文乱码来自终端/附件字符集解码；同一回执中的系统固定文字“成功”也发生相同乱码，因此不属于数据库内容损坏。
- 本次增量未修改 AI worker、模型、GPU 调度、视频流或其他功能菜单。