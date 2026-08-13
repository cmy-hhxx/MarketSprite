# ADR-0001：使用 Symbol Namespace 构成标的身份

- 状态：已接受
- 日期：2026-08-06

## 背景

`Market` 只表达一组共享的交易时区、货币和价格展示惯例。上交所、深交所和北交所都属于 A 股 Market，但不同交易所可以复用同一个证券代码，例如上证指数和平安银行都使用 `000001`。因此 `market:symbol` 或单独的 symbol 都不能稳定区分标的。

腾讯和东方财富还各自拥有 `sh000001`、`1.000001`、`105.AAPL` 等提供方标识。这些标识适合请求路由，却可能随提供方变化，也无法作为跨行情源的领域身份。

## 决策

- 领域模型保存 `symbol`、`name` 和提供方无关的 `SymbolNamespace`。
- `Market` 从 Namespace 计算，不与 Namespace 同时持久化。
- `InstrumentID` 固定为 `namespace:symbol`，例如 `sse:000001`、`szse:000001`、`sse:510300` 和 `us:AAPL`。
- Namespace 当前包含 `sse`、`szse`、`bse`、`hk` 和 `us`。
- 腾讯代码和东方财富 secid 只在行情 adapter 内由 Namespace 映射。
- 东方财富美股的 `105/106/107` QuoteID 只缓存在 adapter 内，不进入 Instrument、JSON 或 SQLite。

## 结果

- 相同 symbol 可以同时存在于搜索结果、Watchlist、提醒目标和数据库中。
- JSON 导入导出必须使用 `namespace`，界面在可能出现歧义的位置显示交易所名称。
- SQLite 主数据库固定为 `marketsprite.sqlite`，保存 `namespace:symbol` 身份；见 [ADR-0002：固定主数据库与内部结构代数](0002-fixed-main-database.md)。
- 新增代码域时必须同时定义 Market 映射、Provider 路由、显示名称和回归测试。
