import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StockStore
    @State private var query = ""
    @State private var results: [StockSymbol] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var selectedSection: SettingsSection = .watchlist
    @State private var isRefreshingAlertPrices = false
    @State private var alertPriceMessage: String?
    @State private var jsonImportText = ""
    @State private var jsonImportMessage: String?
    @State private var showJSONImport = false
    @State private var confirmJSONImport = false
    @State private var confirmClearQuoteDB = false

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 190)
        } detail: {
            Group {
                switch selectedSection {
                case .watchlist:
                    watchlistView
                case .appearance:
                    ScrollView {
                        appearanceView
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                case .alerts:
                    ScrollView {
                        alertsView
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                case .data:
                    ScrollView {
                        dataView
                            .frame(maxWidth: 640, alignment: .topLeading)
                    }
                    .onAppear { store.refreshQuoteBarCount() }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("\(AppIdentity.displayName) 设置")
        .sheet(isPresented: $showJSONImport) {
            jsonImportSheet
        }
    }

    private var watchlistView: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageTitle("桌面股票", subtitle: "搜索名称或代码，也可通过 JSON 批量导入")

            if let sourceError = store.sourceError {
                Label(sourceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                TextField("例如：贵州茅台、00700、AAPL", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("搜索")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)

                Button {
                    fillJSONExample(copyToPasteboard: false, announce: false)
                    showJSONImport = true
                } label: {
                    Text("JSON 导入")
                }
                .buttonStyle(.bordered)
            }

            if let searchMessage {
                Text(searchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results) { symbol in
                        HStack(spacing: 10) {
                            MarketBadge(market: symbol.market)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(symbol.name).fontWeight(.medium)
                                Text(symbol.code)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button(tr(store.symbols.contains(symbol) ? "已添加" : "添加")) {
                                searchMessage = store.add(symbol)
                                if searchMessage == nil {
                                    searchMessage = String(
                                        format: tr("已把 %@ 放到桌面"),
                                        symbol.name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.symbols.contains(symbol))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        if symbol.id != results.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .frame(maxHeight: 148)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(tr("当前")) \(store.symbols.count) \(tr("只"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.symbols.isEmpty {
                    Text("拖动排序")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)

            if store.symbols.isEmpty {
                Text(tr("还没有股票，搜索名称或代码后添加"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                List {
                    ForEach(store.symbols) { symbol in
                        HStack(spacing: 10) {
                            MarketBadge(market: symbol.market)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(symbol.name).fontWeight(.medium)
                                Text("\(symbol.code) · \(symbol.market.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if let quote = store.quotes[symbol.id] {
                                Text(String(format: "%@%.2f%%", quote.changePercent >= 0 ? "+" : "", quote.changePercent))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(symbol.market.colorRole(isRising: quote.changePercent >= 0).color)
                            }
                            Button(role: .destructive) {
                                store.remove(symbol)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(tr("删除"))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowSeparator(.visible)
                    }
                    .onMove(perform: store.moveSymbols)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 720, alignment: .topLeading)
    }

    private var jsonImportSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("通过 JSON 导入"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("关闭")) {
                    showJSONImport = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("必填：code、name、market（aShare / hongKong / unitedStates）。quoteID 可选，缺省时按市场自动推导。导入将替换当前桌面列表。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("填入当前示例") {
                    fillJSONExample(copyToPasteboard: false, announce: true)
                }
                Button("复制到剪贴板") {
                    fillJSONExample(copyToPasteboard: true, announce: true)
                }
                Spacer()
                if let jsonImportMessage {
                    Text(jsonImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            TextEditor(text: $jsonImportText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button {
                    if store.symbols.isEmpty {
                        applyJSONImport()
                    } else {
                        confirmJSONImport = true
                    }
                } label: {
                    Label("导入 JSON", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImportJSON)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .confirmationDialog(
            tr("用 JSON 替换当前桌面股票？"),
            isPresented: $confirmJSONImport,
            titleVisibility: .visible
        ) {
            Button(tr("替换并导入"), role: .destructive) {
                applyJSONImport()
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: tr("当前有 %d 只股票，导入后将被 JSON 中的列表替换，此操作不可撤销。"),
                    store.symbols.count
                )
            )
        }
    }

    private var canImportJSON: Bool {
        let trimmed = jsonImportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return false }
        return true
    }

    private func applyJSONImport() {
        let result = store.importSymbols(fromJSON: jsonImportText)
        jsonImportMessage = result.message
        if case .success = result {
            showJSONImport = false
        }
    }

    private func fillJSONExample(copyToPasteboard: Bool, announce: Bool) {
        let example = store.symbolsJSONExample()
        jsonImportText = example
        if copyToPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(example, forType: .string)
        }
        guard announce else {
            jsonImportMessage = nil
            return
        }
        jsonImportMessage = tr(
            copyToPasteboard ? "已填入编辑框并复制到剪贴板" : "已填入当前股票示例"
        )
    }

    private var appearanceView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("外观与交互", subtitle: "让它融进桌面，而不是挡住工作")

            SettingsCard {
                HStack {
                    Label("整体大小", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $store.displayScale, in: 0.65...1.6, step: 0.05)
                    Text("\(Int(store.displayScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider().opacity(0.5)
                opacitySlider(
                    title: "曲线不透明度",
                    icon: "waveform.path.ecg",
                    value: $store.lineOpacity,
                    range: 0.15...1
                )
                Divider().opacity(0.5)
                opacitySlider(
                    title: "名称与数字不透明度",
                    icon: "textformat",
                    value: $store.labelOpacity,
                    range: 0.35...1
                )
                Divider().opacity(0.5)
                opacitySlider(
                    title: "背景板不透明度",
                    icon: "square.on.square",
                    value: $store.backgroundOpacity,
                    range: 0...0.55
                )
            }

            SettingsCard {
                Toggle(isOn: $store.compactMode) {
                    Label("紧凑模式", systemImage: "rectangle.compress.vertical")
                }
                Divider().opacity(0.5)
                Toggle(isOn: $store.alwaysOnTop) {
                    Label("始终置顶", systemImage: "pin.fill")
                }
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $store.clickThrough) {
                        Label("锁定并穿透鼠标", systemImage: "cursorarrow.slash")
                    }
                    Text("锁定后需从菜单栏的曲线图标关闭穿透。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }

            SettingsCard {
                Toggle(isOn: $store.shortcutEnabled) {
                    Label("快捷键显示/隐藏桌宠", systemImage: "keyboard")
                }
                Divider().opacity(0.5)
                HStack {
                    Text("快捷键组合")
                    Spacer()
                    Picker("", selection: $store.shortcutModifier) {
                        ForEach(ShortcutModifierOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 86)

                    Text("+")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $store.shortcutKey) {
                        ForEach(ShortcutKeyOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)
                }
                .disabled(!store.shortcutEnabled)
                .opacity(store.shortcutEnabled ? 1 : 0.45)
            }

            Button("恢复默认外观") {
                store.resetAppearance()
            }
            .buttonStyle(.bordered)
        }
    }

    private var alertsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle(
                "牛熊提醒",
                subtitle: store.alertBasis == .percentage
                    ? "涨跌幅以昨收为基准，每次越过阈值只提醒一次"
                    : "为每只股票设置小牛价和小熊价，触达目标价格时提醒"
            )

            SettingsCard {
                Toggle(isOn: $store.alertsEnabled) {
                    Label("开启牛熊提醒", systemImage: "bell.badge.fill")
                }
                Divider().opacity(0.5)
                HStack {
                    Label("提醒依据", systemImage: "scope")
                    Spacer()
                    Picker("", selection: $store.alertBasis) {
                        ForEach(AlertBasis.allCases) { basis in
                            Text(basis.displayName).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
                Divider().opacity(0.5)
                Group {
                    if store.alertBasis == .percentage {
                        thresholdRow(
                            title: "上涨超过",
                            mascot: "🐂",
                            value: $store.risingThreshold,
                            color: .red
                        )
                        Divider().opacity(0.5)
                        thresholdRow(
                            title: "下跌超过",
                            mascot: "🐻",
                            value: $store.fallingThreshold,
                            color: .green
                        )
                    } else {
                        priceAlertControls
                    }
                    Divider().opacity(0.5)
                    opacitySlider(
                        title: "提醒不透明度",
                        icon: "circle.lefthalf.filled",
                        value: $store.alertOpacity,
                        range: 0.2...1
                    )
                    Divider().opacity(0.5)
                    Toggle(isOn: $store.bullSoundEnabled) {
                        Label("小牛提示音（短促牛叫）", systemImage: "speaker.wave.2.fill")
                    }
                    Divider().opacity(0.5)
                    Toggle(isOn: $store.bearSoundEnabled) {
                        Label("小熊提示音（短促吼声）", systemImage: "speaker.wave.2.fill")
                    }
                }
                .disabled(!store.alertsEnabled)
                .opacity(store.alertsEnabled ? 1 : 0.45)
            }

            Text(
                tr(
                    store.alertBasis == .percentage
                        ? "股票回到阈值内至少 0.15 个百分点后会重新布防，防止价格在边缘波动时连续弹出。"
                        : "目标价提醒触发后，价格回到目标内侧至少 0.15% 才会重新布防。行情按刷新频率持续更新。"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("预览小牛") {
                    store.testAlert(.rising)
                }
                .buttonStyle(.bordered)
                Button("预览小熊") {
                    store.testAlert(.falling)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var priceAlertControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时价格与逐股目标")
                        .fontWeight(.semibold)
                    Text("先刷新实时价，再一键生成目标或手动调整")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refreshAlertPrices(generateTargets: false)
                } label: {
                    if isRefreshingAlertPrices {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新实时价", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingAlertPrices)
                Button("按现价生成目标") {
                    refreshAlertPrices(generateTargets: true)
                }
                .disabled(isRefreshingAlertPrices)
            }

            if let alertPriceMessage {
                Text(alertPriceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.symbols) { symbol in
                        priceAlertRow(for: symbol)
                        if symbol.id != store.symbols.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 230)
        }
    }

    private func priceAlertRow(for symbol: StockSymbol) -> some View {
        let quote = store.quotes[symbol.id]
        let targets = store.priceAlertTargets[symbol.id]
            ?? PriceAlertTargets(risingPrice: 0, fallingPrice: 0)
        let hasLivePrice = (quote?.lastPrice ?? 0) > 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { targets.isEnabled },
                        set: { store.setPriceTargetsEnabled(for: symbol, enabled: $0) }
                    )
                )
                .labelsHidden()
                .disabled(!hasLivePrice && !targets.isEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.name).fontWeight(.semibold)
                    Text("\(symbol.code) · \(symbol.market.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let quote {
                    Text(
                        String(
                            format: tr("现价 %@%.2f"),
                            symbol.market.currencySymbol,
                            quote.lastPrice
                        )
                    )
                    .font(.body.bold().monospacedDigit())
                } else {
                    Text("等待实时价")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                priceField(
                    title: "🐂 小牛价 ≥",
                    symbol: symbol,
                    isRising: true,
                    value: targets.risingPrice
                )
                priceField(
                    title: "🐻 小熊价 ≤",
                    symbol: symbol,
                    isRising: false,
                    value: targets.fallingPrice
                )
            }
            .disabled(!targets.isEnabled)
            .opacity(targets.isEnabled ? 1 : 0.42)
        }
        .padding(.vertical, 9)
    }

    private func priceField(
        title: String,
        symbol: StockSymbol,
        isRising: Bool,
        value: Double
    ) -> some View {
        HStack(spacing: 6) {
            Text(tr(title))
                .font(.caption)
            Text(symbol.market.currencySymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "",
                value: Binding(
                    get: { value },
                    set: { newValue in
                        let current = store.priceAlertTargets[symbol.id]
                            ?? PriceAlertTargets(risingPrice: 0, fallingPrice: 0)
                        store.updatePriceTargets(
                            for: symbol,
                            risingPrice: isRising ? newValue : current.risingPrice,
                            fallingPrice: isRising ? current.fallingPrice : newValue
                        )
                    }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 92)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAlertPrices(generateTargets: Bool) {
        isRefreshingAlertPrices = true
        alertPriceMessage = nil
        Task {
            await store.refreshAll()
            if generateTargets {
                let count = store.generatePriceTargetsFromCurrentQuotes()
                alertPriceMessage = String(
                    format: tr("已按当前价为 %d 只股票生成目标"),
                    count
                )
            } else {
                alertPriceMessage = tr("实时价格已刷新")
            }
            isRefreshingAlertPrices = false
        }
    }

    private var dataView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("数据与刷新")

            SettingsCard {
                HStack {
                    Label("刷新频率", systemImage: "arrow.clockwise")
                    Spacer()
                    Picker("", selection: $store.refreshInterval) {
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Divider().opacity(0.5)
                LabeledContent("当前数据源", value: tr("腾讯分时 · 东方财富备用"))
                Divider().opacity(0.5)
                LabeledContent(
                    "最近刷新",
                    value: store.lastRefresh?.formatted(
                        Date.FormatStyle(
                            date: .abbreviated,
                            time: .standard,
                            calendar: .current,
                            timeZone: .current
                        )
                    ) ?? tr("尚未连接")
                )
            }

            SettingsCard {
                LabeledContent("A股分钟库行数", value: "\(store.quoteBarCount)")
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("库路径"))
                        .font(.subheadline.weight(.semibold))
                    Text(store.quoteDatabasePath.isEmpty ? tr("未打开") : store.quoteDatabasePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider().opacity(0.5)
                Button(role: .destructive) {
                    confirmClearQuoteDB = true
                } label: {
                    Label("清空行情库", systemImage: "trash")
                }
                .confirmationDialog(
                    tr("清空全部已存 A 股分钟数据？此操作不可撤销。"),
                    isPresented: $confirmClearQuoteDB,
                    titleVisibility: .visible
                ) {
                    Button(tr("清空"), role: .destructive) {
                        store.clearQuoteDatabase()
                    }
                    Button(tr("取消"), role: .cancel) {}
                }
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("立即刷新全部股票", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("使用说明")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 本应用仅用于个人辅助查看，不构成投资建议。")
                    Text("• 公开网页行情可能延迟、限流或调整，不应用于下单决策。")
                    Text("• 港股、美股实时权限受交易所授权约束；若需要交易级数据，可后续接入富途 OpenD 或券商行情。")
                    Text("• 接口失败时不会生成假曲线，只保留最后一次成功数据并标记为过期。")
                    Text("• A 股分钟线会写入本地 SQLite；收盘后至次日开盘前在曲线上标注 B/S 极值。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func runSearch() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        results = []

        Task {
            do {
                let found = try await store.search(cleanQuery)
                results = found
                searchMessage = found.isEmpty ? tr("没有找到支持的 A股、港股或美股") : nil
            } catch {
                searchMessage = String(
                    format: tr("搜索失败：%@"),
                    error.localizedDescription
                )
            }
            isSearching = false
        }
    }

    private func pageTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr(title))
                .font(.title2.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(tr(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private func opacitySlider(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Label(tr(title), systemImage: icon)
                .frame(width: 160, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func thresholdRow(
        title: String,
        mascot: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Text(mascot).font(.system(size: 22))
            Text(tr(title)).frame(width: 80, alignment: .leading)
            Slider(value: value, in: 0.5...15, step: 0.5)
                .tint(color)
            Text(String(format: "%.1f%%", value.wrappedValue))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case watchlist
    case appearance
    case alerts
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchlist: tr("桌面股票")
        case .appearance: tr("外观与交互")
        case .alerts: tr("牛熊提醒")
        case .data: tr("数据与刷新")
        }
    }

    var icon: String {
        switch self {
        case .watchlist: "list.star"
        case .appearance: "paintbrush"
        case .alerts: "bell.badge"
        case .data: "network"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MarketBadge: View {
    let market: StockMarket

    var body: some View {
        Text(market.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(badgeColor)
            .background(badgeColor.opacity(0.14), in: Capsule())
    }

    private var badgeColor: Color {
        switch market {
        case .aShare: .red
        case .hongKong: .orange
        case .unitedStates: .blue
        }
    }
}
