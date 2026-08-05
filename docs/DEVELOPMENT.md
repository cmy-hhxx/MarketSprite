# MarketSprite 开发指南

## 环境

- macOS 14+
- Xcode 16+
- mise

项目使用 `mise.toml` 固定 XcodeGen 版本。首次进入仓库后运行：

```bash
mise trust
mise install
mise exec -- xcodegen generate
open MarketSprite.xcodeproj
```

`project.yml` 是 Xcode 工程的唯一配置来源。修改 target、依赖或构建设置后重新运行 XcodeGen，不要直接维护 `project.pbxproj`。

## 目录

```text
StockPet/
  App/          应用入口、窗口与品牌迁移
  Models/       行情和提醒领域模型
  Services/     搜索与分时行情客户端
  Stores/       应用状态、刷新、提醒与持久化
  Views/        SwiftUI 界面
  Resources/    App Icon 与提醒音效
MarketSpriteTests/
Packages/QuoteDatabase/
docs/
```

产品、target 和 scheme 已统一为 `MarketSprite`。源码目录暂时保留为 `StockPet/`，用于避免在本轮品牌迁移中移动资源路径；它不是对外产品名。

## 验证

运行完整测试：

```bash
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/MarketSpriteDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

验证 Release 构建：

```bash
xcodebuild build \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/MarketSpriteRelease \
  CODE_SIGNING_ALLOWED=NO
```

提交前还应检查：

```bash
rg -n 'MingyHUD|StockPet_my' \
  -g '!build/**' \
  -g '!Packages/QuoteDatabase/.build/**'
git diff --quiet -- StockPet/Resources
```

第二条命令在当前品牌迁移期间必须以状态码 `0` 退出。

## 兼容协议

v0.4.0 将 bundle identifier 从 `com.mingyhud.app` 改为 `io.github.cmy-hhxx.marketsprite`。

- 首次正常启动时，只复制旧偏好域中以 `stockPet.` 开头的值和窗口位置；新域已有值不会被覆盖。
- 旧偏好键名暂时保留，不能在没有新迁移逻辑时直接更名。
- `~/Library/Application Support/MingyHUD` 会复制到 `MarketSprite`。
- 已存在的 MarketSprite 文件不会被旧数据覆盖。
- `NSWindow Frame StockPetFloatingFrame` 会迁移到新偏好域，并继续作为窗口位置保存键。
- 测试进程不会执行真实用户目录迁移。

## 第三方内容

- 行情数据库使用 [GRDB](https://github.com/groue/GRDB.swift)。
- 牛熊提示音的来源记录在 `StockPet/Resources/Sounds/README.md`。
- 上游 StockPet 的 MIT 版权声明必须保留在根目录 `LICENSE`。
