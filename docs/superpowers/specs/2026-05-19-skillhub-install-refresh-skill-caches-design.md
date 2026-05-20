# SkillHub 安装后刷新技能缓存设计

## 背景

SkillHub 安装完成后，SkillHub 页面会显示安装成功，但技能管理页依赖本地 `SkillCacheRepository` 缓存。如果安装完成后不刷新缓存，用户切到技能管理并搜索刚安装的 Skill 时会搜不到，必须手动刷新或重新进入页面。

## 目标

- SkillHub 安装完成后，自动刷新本地已安装 Skill 缓存。
- 刷新行为覆盖 Skill 的增删改变化，不只服务于安装。
- helper 命名为 `refreshSkillCaches()`。
- 不改变现有安装协议和 Gateway 安装流程。

## 非目标

- 不新增 `skills_changed` 协议事件。
- 不要求 Gateway status payload 必须携带目标 `gatewayId`。
- 不改变技能管理页现有搜索和筛选逻辑。
- 不把 SkillHub 页面和技能管理页面做强耦合导航。

## 方案

在客户端提供一个统一 helper：`refreshSkillCaches()`。

1. 读取当前在线且支持 `skills` 能力的 gateway。
2. 对每个 gateway 调用 `SkillCacheRepository.syncGateway(scope, locale)`。
3. 安装完成状态 `skillhub_install_status=installed` 到达时调用 `refreshSkillCaches()`。
4. 刷新失败不回滚安装，也不把安装状态改成失败，只记录调试日志。

选择刷新所有在线 skills gateway，而不是只刷新某一个 gateway。原因是当前 managed install 和 gateway-native install 的完成事件并不总是稳定携带目标 gateway，且本地 gateway 数量少，全量刷新成本可接受。

## 用户体验

- SkillHub 显示安装完成后，技能管理页很快能搜索到新 Skill。
- 用户不需要手动点击技能管理页刷新按钮。
- 如果某个 gateway 暂时不可用，安装结果仍保持成功，技能管理页可继续显示已有缓存。

## 测试

新增或更新 Flutter 测试，覆盖：

- 收到 `skillhub_install_status=installed` 后调用 `refreshSkillCaches()`。
- `refreshSkillCaches()` 会同步所有在线且支持 `skills` 的 gateway。
- 非完成状态，如 `downloading`、`installing`，不触发缓存刷新。
- 某个 gateway 刷新失败时不影响安装状态更新。

## 验收标准

- 安装完成后，技能管理页可以搜索到刚安装的 Skill。
- helper 名称为 `refreshSkillCaches()`。
- 不修改 Server/Gateway 协议字段。
- 现有 SkillHub 安装状态展示不回归。
