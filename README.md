<p align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="MarketSprite 图标">
</p>

<h1 align="center">MarketSprite</h1>

<p align="center">
  <strong>常驻桌面的市场观察与智能提醒助手</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="A股 港股 美股" src="https://img.shields.io/badge/市场-A股%20%7C%20港股%20%7C%20美股-EA4C61">
  <img alt="Version 0.4.0" src="https://img.shields.io/badge/version-0.4.0-5B67F1">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-4C9A2A">
</p>

<p align="center">
  <img src="docs/assets/screenshot-stock-list.webp" width="760" alt="MarketSprite 桌面行情面板">
</p>

MarketSprite 是一个原生 macOS 桌面行情工具。它把自选股、当日分时、最新价和涨跌幅留在桌面边缘，在价格越过阈值时通过小牛或小熊提醒你，而不要求一直打开完整行情软件。

当前版本聚焦可靠的行情观察和提醒。面向行情解释、研究与多 Agent 协作的能力仍在规划中，尚未包含在 v0.4.0。

## 当前能力

- 搜索并关注 A 股、港股和美股，不限制自选股数量。
- 展示真实当日分钟线；腾讯分时失败时自动尝试东方财富。
- 中国内地和香港市场红涨绿跌，美股绿涨红跌。
- 按昨收涨跌幅或逐股目标价格触发牛熊提醒。
- 回到阈值内侧后才重新布防，避免价格在边缘反复提醒。
- 调节整体缩放、紧凑模式、曲线/文字/背景透明度。
- 支持始终置顶、拖动、鼠标穿透和全局显示/隐藏快捷键。
- 通过 JSON 批量导入自选股。
- 将 A 股分钟数据写入本地 SQLite，并在收盘后显示当日 B/S 极值。

## 使用

1. 启动应用后，双击桌面行情面板打开设置。
2. 搜索名称或代码，例如 `贵州茅台`、`00700`、`AAPL`。
3. 在“牛熊提醒”中选择涨跌幅或目标价格，并设置提醒阈值。
4. 在“外观与交互”中调整透明度、置顶、鼠标穿透和快捷键。

默认显示/隐藏快捷键为 `⌘ + ⌥ + S`。开启鼠标穿透后，可从菜单栏的曲线图标重新关闭。

## 从源码构建

当前仓库暂未提供已签名的安装包，需要从源码构建：

```bash
git clone https://github.com/cmy-hhxx/MarketSprite.git
cd MarketSprite
mise install
mise exec -- xcodegen generate
open MarketSprite.xcodeproj
```

要求：

- macOS 14 或更高版本
- Xcode 16 或更高版本
- [mise](https://mise.jdx.dev/)

命令行测试：

```bash
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

更多开发约定见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 数据与隐私

- 股票搜索会访问东方财富，分时行情优先访问腾讯并以东方财富备用。
- 自选股、显示设置和提醒设置保存在本机偏好中。
- A 股分钟数据保存在 `~/Library/Application Support/MarketSprite/quotes.sqlite`。
- 应用不包含账号系统、广告、埋点或遥测。
- 从 MingyHUD 升级时，MarketSprite 会复制旧偏好和数据库；旧数据不会被删除或覆盖。

完整说明见 [docs/PRIVACY.md](docs/PRIVACY.md)。公开网页行情可能延迟、限流或调整，不应作为下单依据。

> [!CAUTION]
> MarketSprite 仅用于个人辅助查看行情，不构成投资建议。任何投资决策及其结果由使用者自行承担。

## 路线

- 将行情、公告和本地自选股整理为统一上下文。
- 引入可解释的市场观察 Agent，而不是直接生成交易指令。
- 为 Agent 增加明确的权限边界、来源标注和隐私控制。

路线仅表示方向，不代表已经交付或承诺发布时间。

## 来源与许可

MarketSprite 基于 [YellowPancake/StockPet](https://github.com/YellowPancake/StockPet) 的 MIT 授权代码继续开发。原作者版权声明已保留在 [LICENSE](LICENSE) 中。

提醒音效的来源与 CC0 说明见 [StockPet/Resources/Sounds/README.md](StockPet/Resources/Sounds/README.md)。本项目采用 [MIT License](LICENSE)。
