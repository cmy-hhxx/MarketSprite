<p align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="MarketSprite 牛熊行情应用图标">
</p>

<h1 align="center">MarketSprite</h1>

<p align="center">
  <strong>把真正关心的行情，安静地放在桌面上。</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-63D3B7?logo=apple&logoColor=20242A">
  <img alt="原生 SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-68B8ED?logo=swift&logoColor=20242A">
  <img alt="A股、港股和美股" src="https://img.shields.io/badge/市场-A股%20%7C%20港股%20%7C%20美股-FF6652">
  <img alt="本地优先" src="https://img.shields.io/badge/数据-本地优先-FFF1D8">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-63D3B7">
</p>

<p align="center">
  <img src="docs/assets/readme/hero.webp" width="900" alt="MarketSprite 牛熊图标与真实 B/S 桌面行情面板">
</p>

MarketSprite 是一个原生 macOS 桌面行情与价格提醒工具。它持续展示观察列表中的当日分时、最新价和涨跌幅，在价格越过明确阈值时提醒你，但不替你做交易决定。

它适合只想随手看一眼关键标的、不想一直开着完整交易终端的人。

## 为什么是 MarketSprite

<table>
  <tr>
    <td width="33%"><strong>常驻但不打扰</strong><br><br>窗口置顶、透明度、整体缩放、紧凑模式和鼠标穿透都可调整，让行情融入桌面。</td>
    <td width="33%"><strong>真实分时，不画假线</strong><br><br>腾讯分时失败时尝试东方财富；网络失败则保留最后一次成功行情并明确标记过期。</td>
    <td width="33%"><strong>提醒可解释</strong><br><br>按昨收涨跌幅或逐标的目标价格触发；回到阈值内侧后才重新布防，避免边缘反复弹出。</td>
  </tr>
</table>

## 核心能力

- 搜索并观察 A 股、港股和美股；相同代码会显示所属交易所，避免混淆。
- 展示真实当日分钟线、最新价、涨跌幅和行情更新时间。
- 中国内地与香港市场使用红涨绿跌，美股使用绿涨红跌。
- 支持任意数量的观察标的、拖动排序和 JSON 批量替换。
- 支持涨跌幅提醒、逐标的目标价格提醒以及独立牛熊提示音。
- 支持整体缩放、紧凑模式、曲线/文字/背景透明度和提醒透明度。
- 支持始终置顶、鼠标穿透和全局显示/隐藏快捷键。
- 将观察标的与分钟行情保存在本地 SQLite；A 股收盘后显示复盘 B/S：S 为最高分钟收盘价，B 仅标注随后出现上涨的最低分钟收盘价，不构成交易建议。

## 牛熊提醒

<p align="center">
  <img src="docs/assets/readme/mascots.webp" width="680" alt="MarketSprite 小牛和小熊提醒角色">
</p>

- 小牛负责上涨或上穿目标价格提醒。
- 小熊负责下跌或下穿目标价格提醒。
- 同一方向触发后必须先回到阈值内侧，才会再次布防。
- 提醒只表达你预先设置的条件，不分析买卖机会，也不会自动下单。

## 使用

1. 启动应用，双击桌面行情面板打开设置。
2. 搜索名称或代码，例如 `贵州茅台`、`00700`、`AAPL`。
3. 将标的加入观察列表并拖动排序。
4. 在“牛熊提醒”中选择涨跌幅或目标价格，设置对应阈值。
5. 在“外观与交互”中调整透明度、置顶、鼠标穿透和快捷键。

默认显示/隐藏快捷键为 `⌘ + ⌥ + S`。开启鼠标穿透后，可以从菜单栏的稀疏注意力轨迹图标重新关闭。

## 从源码构建

仓库使用 `project.yml` 生成本地 Xcode 工程，`MarketSprite.xcodeproj` 不纳入版本控制。

```bash
git clone https://github.com/cmy-hhxx/MarketSprite.git
cd MarketSprite
mise trust
mise install
mise exec -- xcodegen generate
open MarketSprite.xcodeproj
```

要求：macOS 14 或更高版本、Xcode 16 或更高版本，以及 [mise](https://mise.jdx.dev/)。

提交前验证：

```bash
Scripts/test.sh

# 性能测试
Scripts/test.sh performance
```

日常开发只需要记住两个入口：`Scripts/test.sh` 负责测试、性能测试和清理，`Scripts/install_local_app.sh` 负责本机安装。架构校验和 DMG 打包脚本由这些入口调用；只有需要单独检查或制作发布产物时才直接运行。

> [!IMPORTANT]
> 测试和安装必须使用项目脚本，不要直接执行裸 `xcodebuild test`，也不要手工复制或拖拽 `.app`。`Scripts/test.sh` 会在测试结束后清理临时应用及系统注册记录；`Scripts/install_local_app.sh` 是唯一的本机安装入口，最终只保留 `/Applications/MarketSprite.app`。如果历史操作已经产生了多余副本，运行 `Scripts/test.sh cleanup`。

## 数据与隐私

- 标的搜索访问东方财富；分时行情优先访问腾讯并以东方财富备用。
- 观察列表、标的、提醒配置、目标价格和最新交易日行情缓存保存在 `~/Library/Application Support/MarketSprite/marketsprite.sqlite`。
- 外观、刷新频率、声音、窗口行为和快捷键保存在 macOS 用户偏好中。
- 应用没有账号系统、云同步、广告、埋点或遥测。

完整说明见 [隐私说明](docs/PRIVACY.md)。公开网页行情可能延迟、限流或调整，不应作为下单依据。

> [!CAUTION]
> MarketSprite 仅用于个人辅助查看行情，不构成投资建议。任何投资决策及其结果由使用者自行承担。

## 产品边界

当前版本不包含持仓核算、券商连接、自动下单、后台全市场扫描、Pi Agent 或 TUI。后续 Dashboard 也只会在用户主动进入时启动，不改变桌面观察列表的克制形态。

这些方向不代表已经交付或承诺发布时间。

## 开发文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发指南](docs/DEVELOPMENT.md)
- [隐私说明](docs/PRIVACY.md)
- [更新记录](CHANGELOG.md)

## 来源与许可

MarketSprite 基于 [YellowPancake/StockPet](https://github.com/YellowPancake/StockPet) 的 MIT 授权代码继续开发，原作者版权声明保留在 [LICENSE](LICENSE) 中。

提醒音效的来源与 CC0 说明见 [MarketSprite/Resources/Sounds/README.md](MarketSprite/Resources/Sounds/README.md)。项目采用 [MIT License](LICENSE)。
