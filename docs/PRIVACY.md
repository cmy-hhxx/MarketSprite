# MarketSprite 隐私说明

更新日期：2026-08-05

## 本地数据

MarketSprite 不要求注册账号。以下数据保存在本机：

- 自选股、外观、快捷键和提醒配置：macOS 用户偏好域 `io.github.cmy-hhxx.marketsprite`。
- A 股分钟行情缓存：`~/Library/Application Support/MarketSprite/quotes.sqlite`。

从 MingyHUD 首次升级时，应用会复制旧偏好和 `~/Library/Application Support/MingyHUD` 中的数据。为了支持降级和人工恢复，迁移不会删除旧目录。

## 网络请求

应用直接访问公开行情服务：

- `searchapi.eastmoney.com`：股票名称或代码搜索。
- `web.ifzq.gtimg.cn`：首选分钟行情。
- `push2delay.eastmoney.com`：备用分钟行情。

搜索词、股票代码、IP 地址以及普通 HTTP 请求元数据可能由这些第三方服务处理。MarketSprite 无法控制第三方服务的日志、限流或数据授权策略。

## 不收集的内容

当前版本不包含：

- MarketSprite 账号或云同步。
- 广告、行为分析、崩溃遥测或用户画像。
- 券商账号、交易凭据或自动下单。
- 已上线的 AI/Agent 服务。

未来接入 Agent、模型 API 或云端服务前，必须先更新本文档，并在产品中说明发送的数据、用途、服务提供方和用户控制方式。

## 删除数据

退出应用后，可以在 Finder 中打开应用数据目录，将 `MarketSprite` 文件夹移到废纸篓：

```bash
open "$HOME/Library/Application Support"
```

偏好设置可以通过终端清理：

```bash
defaults delete io.github.cmy-hhxx.marketsprite
```

确认不再需要从旧版本恢复后，可另行将旧的 `MingyHUD` 文件夹移到废纸篓。

## 风险说明

公开网页行情可能延迟、不完整、限流或随时调整。MarketSprite 仅用于个人辅助查看，不构成投资建议，也不应作为下单依据。
