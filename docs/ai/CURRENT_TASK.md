# 当前任务看板

> 最后更新：2026-07-21 13:07（北京时间）

## 当前任务

- 让管理员补全正式库空字段时，同步形成可追溯的贡献记录和权威积分流水，且不破坏现有审核与衣柜写回流程。

## 为什么做

- 用户中心已经读取权威积分汇总，但正式库补全尚未写入贡献与积分事实，实际完成有效补全的用户仍无法获得应有的 5 分。

## 已经完成

- DB-1 贡献与积分事实表、DB-2 最小只读接口及个人中心权威积分展示均已进入 `develop`。
- 已确认本轮只接入正式库空字段补全：有效提交者按最早时间去重后最多 5 人，每人 5 分，并与衣柜写回、pending 通过保持同一事务。
- DB-3 两个 migration 已应用到 development：正式库补全、贡献、每人 5 分、衣柜写回和 pending 通过保持同一事务；重试 patch 未改写已应用 migration 历史。
- development 完整事务矩阵已通过：普通用户拒绝、admin / super_admin、前 5 去重、反序重试幂等、DB-2 汇总和故障回滚均符合契约；合成 fixture 全部 rollback，贡献与积分事实表恢复为 0 行。
- schema / types、Security / Performance Advisor、7 项 Node tests 与生产构建已复核；已准备一条不含积分的 development 人工验收夹具。

## 当前进度

- 验证阶段：实现、development 自动验证和 Draft [PR #87](https://github.com/larissa2022/nikki-calculator/pull/87) 已发布，Preview 检查通过；业务状态保持待负责人通过 development / Preview 完成人工验收。

## 下一步

- 负责人使用验收夹具完成一次正式库空字段补全，并回传结果或异常。

## 需要负责人决定

- 当前只需反馈人工验收结果；是否 merge、是否清理验收数据均在结果确认后单独决定。

## 通用边界

- 不操作 `main`、production、Vercel、env，不接入管理员仲裁、自动入库、重审、排行榜或复杂权益。
- 不开放贡献与积分底表客户端权限，不回填历史，不删除或改写既有积分流水。

## Rollback

- RPC 异常时通过新 patch migration 恢复上一版函数定义；不改写已应用 migration 历史。
- 错误积分以反向流水修正，不删除历史；development 测试数据按验证方案回滚或显式清理。
