# MarketSprite 隐私说明

更新日期：2026-08-11

## 本地数据

MarketSprite 不要求注册账号。以下数据保存在本机：

- 观察列表、标的信息、提醒配置、逐标的目标价格和分钟行情：`~/Library/Application Support/MarketSprite/marketsprite-v3.sqlite`。
- 外观、刷新频率、声音、窗口行为和快捷键：macOS 用户偏好域 `io.github.cmy-hhxx.marketsprite`。

v0.6.0 不读取、复制、删除或迁移 `marketsprite-v2.sqlite`。MingyHUD/StockPet 的旧偏好和数据库同样不会被读取或自动删除。

## 网络请求

应用直接访问公开行情服务：

- `searchapi.eastmoney.com`：标的名称或代码搜索，以及必要的数据源标识解析。
- `web.ifzq.gtimg.cn`：首选分钟行情。
- `push2delay.eastmoney.com`：备用分钟行情。

搜索词、标的代码、IP 地址以及普通 HTTP 请求元数据可能由这些第三方服务处理。MarketSprite 无法控制第三方服务的日志、限流或数据授权策略。

## 不收集的内容

当前版本不包含：

- MarketSprite 账号、云同步或服务器端数据存储。
- 广告、行为分析、崩溃遥测或用户画像。
- 持仓、成本、券商账号、交易凭据或订单。
- 自动下单或后台自动交易。
- 已上线的 AI、Agent、Pi 或模型 API 服务。

未来接入 Agent、模型 API、云端服务或券商能力前，必须先更新本文档，并在产品中说明发送的数据、用途、服务提供方和用户控制方式。

## 删除数据

应用内可以清空已存分钟行情。若要删除当前数据库数据，请退出应用后，将数据库及可能存在的 `-wal`、`-shm` 同名文件移到废纸篓：

```text
~/Library/Application Support/MarketSprite/marketsprite-v3.sqlite
```

偏好设置可以通过终端清理：

```bash
defaults delete io.github.cmy-hhxx.marketsprite
```

## 风险说明

公开网页行情可能延迟、不完整、限流或随时调整。MarketSprite 仅用于个人辅助查看，不构成投资建议，也不应作为下单依据。
