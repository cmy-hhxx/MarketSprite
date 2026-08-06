# 市场观察

MarketSprite 帮助一个人在桌面上持续关注少量、明确的市场标的，而不是把桌面变成交易终端。这个上下文只覆盖观察、行情和由人配置的提醒，不包含持仓、订单或自动交易。

## 语言

**市场（Market）**:
一组共享交易时区和价格展示惯例的标的范围，目前包括 A 股、港股和美股。
_Avoid_: Exchange、Region、地区

**标的代码域（Symbol Namespace）**:
提供方无关、足以解释证券代码归属的代码空间，目前包括上交所 `sse`、深交所 `szse`、北交所 `bse`、港交所 `hk` 和美股 `us`。Market 从代码域计算；同属 A 股的不同代码域仍可拥有相同 symbol。
_Avoid_: Provider Quote ID、SecID、行情源市场号

**标的（Instrument）**:
用户可以观察的一项市场交易证券，其身份不依赖任何行情提供方。
_Avoid_: Stock、股票项、Asset

**标的 ID（Instrument ID）**:
一个标的跨行情源、刷新、本地存储和应用启动保持不变的身份，格式为 `namespace:symbol`，例如 `sse:000001` 与 `szse:000001`。
_Avoid_: Quote ID、Provider Code、行情代码

**分钟线（Minute Bar）**:
一个市场分钟内观察到的开盘价、收盘价、最高价和最低价。
_Avoid_: Intraday Point、Trend Point、分时点

**行情快照（Quote Snapshot）**:
对一个标的当前交易日的一次完整观察，包含最新价、参考价格、分钟线、来源和观察时间。
_Avoid_: Stock Quote、Live Record、股票行情对象

**观察列表（Watchlist）**:
用户在桌面行情面板中持续查看的有序、持久化标的集合。观察列表表达注意力，不表达所有权。
_Avoid_: Portfolio、Holdings、Favorites、自选股、持仓

**受监控标的（Monitored Instrument）**:
一个标的在桌面行情面板中的当前形态，包含最近的行情快照和新鲜度状态。
_Avoid_: Watchlist Item、Stock Item、列表项

**提醒配置（Alert Configuration）**:
用户用于判断何种市场变化值得打断自己的共享规则。
_Avoid_: Alarm Settings、Strategy、策略

**价格提醒目标（Price Alert Targets）**:
一个标的可选的上行价和下行价，跨过后产生提醒事件。
_Avoid_: Buy Price、Sell Price、Order Trigger、买卖点

**提醒事件（Alert Event）**:
标的跨过已启用涨跌幅或价格阈值后产生的一次、可重新布防的通知。
_Avoid_: Signal、Trade Signal、Recommendation、交易信号

**Dashboard**:
用户主动进入、用于更广市场探索的工作区。它不同于常驻桌面的观察列表，未打开时不运行。
_Avoid_: Watchlist、Portfolio、观察列表

**全市场扫描（Market Scan）**:
Dashboard 内针对广泛市场范围执行的主动分析，而不是针对用户观察列表的后台监控。
_Avoid_: Background Monitor、Automatic Strategy、后台策略
