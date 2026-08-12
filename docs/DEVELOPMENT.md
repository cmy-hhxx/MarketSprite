# MarketSprite 开发指南

## 环境

- macOS 14+
- Xcode 16+
- mise

项目使用 `mise.toml` 固定 XcodeGen、yq 和 ripgrep 版本。首次进入仓库后运行：

```bash
mise trust
mise install
mise exec -- xcodegen generate
open MarketSprite.xcodeproj
```

`project.yml` 是 target、依赖、版本和构建设置的唯一来源。`MarketSprite.xcodeproj` 与 `Package.resolved` 都是本地生成物，不提交到 Git，也不要直接维护 `project.pbxproj`。

## 目录

```text
MarketSprite/
  App/         应用入口、依赖组装与生命周期
  Monitor/     观察列表、刷新编排与桌面行情面板
  MarketData/  市场模型、稳定标识、数据源适配与解析
  Alerts/      提醒规则、评估、展示与声音
  Settings/    应用偏好和设置界面
  Database/    唯一的 SQLite / GRDB 数据访问实现
  Platform/    AppKit 窗口与全局快捷键适配
  Resources/   本地化、图标与声音
MarketSpriteTests/
  Alerts/
  Database/
  MarketData/
  Monitor/
  Settings/
  Support/
Scripts/
docs/
```

领域词汇以根目录 [CONTEXT.md](../CONTEXT.md) 为准，能力依赖与持久化所有权见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 代码边界

- 只有 `Database/` 可以导入 GRDB；所有数据库操作必须通过 `MarketDatabase`。
- 只有 `Settings/AppPreferences.swift` 可以访问 `UserDefaults`。
- 只有 `MarketData/PublicMarketDataClient.swift` 可以发起行情网络请求。
- `InstrumentID` 必须使用 `namespace:symbol`，并独立于腾讯、东方财富或未来数据源的标识。
- `MonitorStore` 负责观察列表运行态、缓存新鲜度、刷新与提醒编排，不负责未来全市场 Dashboard。
- 不增加兼容别名、迁移层、空协议、占位目录或仅转发调用的包装模块。
- Pi Agent、TUI、策略和自动交易均不在当前实现范围；出现真实用例后再设计接口。

新增能力前先判断它是否属于现有能力。只有当新行为拥有独立生命周期和明确接口时，才新增顶层目录。

## 持久化

`MarketDatabase` 使用 `~/Library/Application Support/MarketSprite/marketsprite-v3.sqlite`，保存：

- Instruments 与有序 Watchlist
- 所有支持 Market 的 Quote Snapshots 与 Minute Bars
- Alert Configuration 与逐标的 Price Alert Targets
- 应用初始化元数据

`AppPreferences` 使用当前 bundle 的 macOS 用户偏好域，只保存外观、刷新频率、声音、窗口行为和快捷键。

v0.1.0 只接受当前完整 schema，不注册 migration。它不读取、复制、删除或迁移 `marketsprite-v2.sqlite`；旧文件与新库使用不同文件名。

## 测试

测试目录镜像生产能力。测试应通过公开接口观察行为：

- 行情适配器通过 `MarketDataClient` seam 测试。
- 数据库测试使用真实的内存库、临时文件库或只读 SQLite，不模拟 GRDB 内部调用。
- Monitor 测试验证观察列表、缓存、新鲜度和刷新结果，不读取内部表来旁证。
- 刷新测试必须验证 single-flight 和全局最多 6 个并发请求；数据库测试必须验证完整快照修正与删除。
- 纯规则如 `AlertEvaluator` 和 `Watchlist` 直接测试输入与输出。

生成工程并运行完整测试：

```bash
mise exec -- xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/MarketSpriteDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

运行不设绝对耗时门槛的性能基线（10/100 标的刷新、240 根分钟线、一年缓存和图表渲染）：

```bash
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme MarketSpritePerformance \
  -destination 'platform=macOS' \
  -derivedDataPath build/MarketSpritePerformance \
  CODE_SIGNING_ALLOWED=NO
```

验证 Release 构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/MarketSpriteRelease \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='arm64 x86_64' \
  CODE_SIGNING_ALLOWED=NO
```

## 制作 DMG

发布脚本会构建 Universal Release、执行 ad-hoc 签名、生成品牌化 HiDPI 安装窗口，并重新挂载校验版本、双架构、签名和 Applications 链接：

```bash
Scripts/build_release_dmg.sh
```

产物位于 `build/Dist/MarketSprite-<version>.dmg`。DMG 使用固定版本的 `dmgbuild`；`project.yml` 是应用版本、构建号和文件名的唯一来源。

需要修改安装背景时，编辑 `Distribution/DMG/generate_background.py`，再重新生成 1×/2× 资源：

```bash
mise exec -- uv run --with pillow==12.3.0 \
  python Distribution/DMG/generate_background.py
```

## 架构校验

提交前先运行：

```bash
Scripts/verify_architecture.sh
```

脚本会检查能力目录、旧命名、GRDB/UserDefaults/URLSession 的访问位置、Swift 6 设置、旧 migration 与数据库路径以及生成物忽略规则。它不能替代测试和代码审查，但可以阻止最容易反复出现的结构退化。

## 第三方内容

- SQLite 访问使用 [GRDB](https://github.com/groue/GRDB.swift)，版本由 `project.yml` 精确固定。
- 牛熊提示音来源记录在 [MarketSprite/Resources/Sounds/README.md](../MarketSprite/Resources/Sounds/README.md)。
- 上游 StockPet 的 MIT 版权声明必须保留在根目录 [LICENSE](../LICENSE) 中。
