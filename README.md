<p align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="MarketSprite 图标">
</p>

<h1 align="center">MarketSprite</h1>

<p align="center">
  <strong>极简、常驻桌面的市场观察与提醒工具</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="A股 港股 美股" src="https://img.shields.io/badge/市场-A股%20%7C%20港股%20%7C%20美股-EA4C61">
  <img alt="Version 0.5.0" src="https://img.shields.io/badge/version-0.5.0-5B67F1">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-4C9A2A">
</p>

<p align="center">
  <img src="docs/assets/screenshot-watchlist.webp" width="760" alt="MarketSprite 桌面行情面板">
</p>

MarketSprite 是一个原生 macOS 桌面行情工具。用户把真正关心的标的放进观察列表，应用在桌面边缘持续展示当日分时、最新价和涨跌幅，并在价格跨过明确阈值时给出小牛或小熊提醒。

它首先服务于人：安静、随手可看、不替用户作交易决定。当前版本不包含持仓核算、券商连接、自动下单、Pi Agent、TUI 或后台全市场扫描。

## 当前能力

- 搜索并观察 A 股、港股和美股，不限制观察列表数量；相同代码会显示所属交易所以避免混淆。
- 展示真实当日分钟线；腾讯分时失败时自动尝试东方财富。
- 中国内地和香港市场红涨绿跌，美股绿涨红跌。
- 启动时恢复本地缓存；网络失败时保留最后一次成功行情并明确标记为过期。
- 按昨收涨跌幅或逐标的目标价格触发牛熊提醒。
- 回到阈值内侧后才重新布防，避免价格在边缘反复提醒。
- 调节整体缩放、紧凑模式、曲线/文字/背景透明度。
- 支持始终置顶、拖动、鼠标穿透和全局显示/隐藏快捷键。
- 通过 JSON 批量导入并替换观察列表。
- 将所有已观察市场的分钟行情写入本地 SQLite；A 股收盘后显示当日 B/S 极值。

## 使用

1. 启动应用后，双击桌面行情面板打开设置。
2. 搜索名称或代码，例如 `贵州茅台`、`00700`、`AAPL`。
3. 把任意支持的标的加入观察列表并拖动排序。
4. 在“牛熊提醒”中选择涨跌幅或目标价格，并设置提醒阈值。
5. 在“外观与交互”中调整透明度、置顶、鼠标穿透和快捷键。

默认显示/隐藏快捷键为 `⌘ + ⌥ + S`。开启鼠标穿透后，可从菜单栏的曲线图标重新关闭。

## 从源码构建

仓库使用 `project.yml` 生成本地 Xcode 工程；`MarketSprite.xcodeproj` 不纳入版本控制。

```bash
git clone https://github.com/cmy-hhxx/MarketSprite.git
cd MarketSprite
mise trust
mise install
mise exec -- xcodegen generate
open MarketSprite.xcodeproj
```

要求：

- macOS 14 或更高版本
- Xcode 16 或更高版本
- [mise](https://mise.jdx.dev/)

提交前验证：

```bash
Scripts/verify_architecture.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/MarketSpriteDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

目录与依赖规则见 [架构说明](docs/ARCHITECTURE.md)，完整开发约定见 [开发指南](docs/DEVELOPMENT.md)。

## 数据与隐私

- 标的搜索访问东方财富；分时行情优先访问腾讯并以东方财富备用。
- 观察列表、标的、提醒配置、目标价格和所有已缓存分钟行情保存在 `~/Library/Application Support/MarketSprite/marketsprite-v2.sqlite`。
- 外观、刷新频率、声音、窗口行为和快捷键保存在 macOS 用户偏好中。
- 应用不包含账号系统、云同步、广告、埋点或遥测。
- v0.5.0 是一次破坏性结构升级，不读取 MingyHUD/StockPet 的旧偏好或数据库，也不迁移旧 `marketsprite.sqlite`。

完整说明见 [隐私说明](docs/PRIVACY.md)。公开网页行情可能延迟、限流或调整，不应作为下单依据。

> [!CAUTION]
> MarketSprite 仅用于个人辅助查看行情，不构成投资建议。任何投资决策及其结果由使用者自行承担。

## 后续方向

- Dashboard：只有用户主动进入时才启动全市场浏览或扫描，不改变桌面观察列表的克制形态。
- Pi Agent / TUI：在交互方式和进程边界明确后再接入，当前代码不放置占位实现。
- 策略：优先可解释、可追溯、由人触发和判断，不自动下单。

这些方向不代表已经交付或承诺发布时间。

## 来源与许可

MarketSprite 基于 [YellowPancake/StockPet](https://github.com/YellowPancake/StockPet) 的 MIT 授权代码继续开发。原作者版权声明已保留在 [LICENSE](LICENSE) 中。

提醒音效的来源与 CC0 说明见 [MarketSprite/Resources/Sounds/README.md](MarketSprite/Resources/Sounds/README.md)。本项目采用 [MIT License](LICENSE)。
