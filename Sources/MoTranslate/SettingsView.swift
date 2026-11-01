import SwiftUI
import AppKit

// MARK: - 设置窗口

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsModel
    var onClose: () -> Void

    @State private var revealKey = false
    @State private var testState: TestState = .idle
    @State private var draftName = ""
    @State private var draftBaseURL = ""
    @State private var draftModel = ""
    @State private var draftAPIKey = ""
    @State private var selectedPresetID = ""
    @State private var saveHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("让墨译适合你的工作方式").font(.system(size: 20, weight: .semibold))
                    Text("设置自动保存，随时回到翻译。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onClose() } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .help("关闭设置并回到翻译面板")
            }.padding(.horizontal, 24).padding(.top, 20)
            TabView {
                settingsPage { apiCard; customModelCard; scheduleCard }
                    .tabItem { Label("翻译服务", systemImage: "network") }
                settingsPage { behaviorCard; selectionCard }.tabItem { Label("通用与快捷键", systemImage: "keyboard") }
                settingsPage { aboutCard }.tabItem { Label("关于墨译", systemImage: "info.circle") }
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16, content: content)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: API

    private var apiCard: some View {
        SettingsCard(title: "翻译接口") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("主接口")
                        .font(.system(size: 12))
                        .frame(width: 78, alignment: .leading)
                    Picker("", selection: $settings.primaryEntryID) {
                        ForEach(settings.library) { entry in
                            Text(entry.name).tag(entry.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    Spacer()
                }

                if let entry = settings.primaryEntry {
                    endpointHint(entry)
                    labeledField("API Key", text: keyBinding(entry.keyAccount),
                                 placeholder: isLocal(entry) ? "本地模型可留空" : "sk-…",
                                 secure: !revealKey)
                }

                HStack(spacing: 8) {
                    Toggle("显示密钥", isOn: $revealKey)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Spacer()

                    if case .running = testState {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    }

                    Button("测试连接") { runTest() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!settings.isConfigured || isTesting)
                }

                testStatus
            }
        }
    }

    // MARK: 自有模型库

    private var customModelCard: some View {
        SettingsCard(title: "自有模型库") {
            VStack(alignment: .leading, spacing: 10) {
                Text("填好 Base URL 和模型标识后保存，之后在高峰、谷时和主面板里都能直接选择，不用重复填写。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text("从预设添加")
                        .font(.system(size: 12))
                        .frame(width: 78, alignment: .leading)
                    Picker("", selection: $selectedPresetID) {
                        Text("选择服务商与模型…").tag("")
                        ForEach(settings.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    Spacer()
                }
                .onChange(of: selectedPresetID) { _, id in
                    guard let preset = settings.presets.first(where: { $0.id == id }) else { return }
                    draftName = preset.name
                    draftBaseURL = preset.baseURL
                    draftModel = preset.model
                    saveHint = nil
                }

                labeledField("名称", text: $draftName, placeholder: "可选，默认使用模型名")
                labeledField("Base URL", text: $draftBaseURL, placeholder: "https://api.example.com/v1")
                labeledField("模型", text: $draftModel, placeholder: "model-name")
                labeledField("API Key", text: draftKeyBinding,
                             placeholder: "保存后按服务商保存在钥匙串", secure: !revealKey)

                HStack(spacing: 8) {
                    if let saveHint {
                        Text(saveHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button("保存到模型库") { saveCustomModel() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(draftBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
                                  || draftModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !settings.customModels.isEmpty {
                    Divider().opacity(0.5)
                    ForEach(settings.customModels) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name).font(.system(size: 12))
                                Text("\(entry.model) · \(entry.baseURL)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { settings.removeCustomModel(entry.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("从模型库移除")
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text("预设目录核对自 models.dev（2026-10），实际可调用代号以服务商文档为准。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Link("查看目录", destination: URL(string: "https://models.dev")!)
                        .font(.system(size: 10.5))
                }
            }
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            Text("正在请求接口…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .success(let message):
            Text("✓ \(message)")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failure(let message):
            Text("✕ \(message)")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    // MARK: 峰谷调度

    private var scheduleCard: some View {
        SettingsCard(title: "峰谷调度") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("按时间段切换模型（默认关闭）", isOn: $settings.scheduleEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Text("高峰时段使用上面的主接口，其余时间改用下面的谷时接口。可以把云端模型留给闲时、本地模型留给高峰。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.scheduleEnabled {
                    HStack(spacing: 8) {
                        Text("高峰时段")
                            .font(.system(size: 12))
                            .frame(width: 78, alignment: .leading)
                        timeField(\.peakStart1)
                        Text("–").foregroundStyle(.secondary)
                        timeField(\.peakEnd1)
                        Text("、").foregroundStyle(.secondary)
                        timeField(\.peakStart2)
                        Text("–").foregroundStyle(.secondary)
                        timeField(\.peakEnd2)
                        Spacer()
                    }

                    Toggle("周末全天按空闲时段", isOn: $settings.weekendIsOffPeak)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    Divider().opacity(0.5)

                    Text("谷时接口")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Text("模型")
                            .font(.system(size: 12))
                            .frame(width: 78, alignment: .leading)
                        Picker("", selection: $settings.offPeakEntryID) {
                            Text("沿用主接口").tag("")
                            ForEach(settings.library) { entry in
                                Text(entry.name).tag(entry.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 300)
                        Spacer()
                    }

                    if let entry = settings.offPeakEntry {
                        endpointHint(entry)
                        if entry.keyAccount == settings.primaryEntry?.keyAccount {
                            Text("与主接口使用同一服务商，共用上面的 API Key。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 88)
                        } else {
                            labeledField("API Key", text: keyBinding(entry.keyAccount),
                                         placeholder: isLocal(entry) ? "本地模型可留空" : "sk-…",
                                         secure: !revealKey)
                        }
                    }

                    Text("当前生效：\(settings.activeTierSummary)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("按本机时区判断；中国法定节假日无法自动识别，需要时请临时关闭调度。DeepSeek 官方高峰为工作日 9:00–12:00、14:00–18:00。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func timeField(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> some View {
        DatePicker("", selection: timeBinding(keyPath), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 82)
    }

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings[keyPath: keyPath]
                var components = DateComponents()
                components.hour = minutes / 60
                components.minute = minutes % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    // MARK: 翻译行为

    private var behaviorCard: some View {
        SettingsCard(title: "翻译行为") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目标语言")
                        .font(.system(size: 12))
                        .frame(width: 78, alignment: .leading)
                    Picker("", selection: $settings.targetMode) {
                        ForEach(TargetMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 260)
                    Spacer()
                }

                Toggle("输入时自动翻译", isOn: $settings.autoTranslate)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("流式输出（边生成边显示）", isOn: $settings.streamingEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("识别 Markdown 结构（保留代码块与语法，默认开启）", isOn: $settings.markdownEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("打开面板时自动读取剪贴板", isOn: $settings.fillFromClipboard)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("固定翻译面板，点击外部时保持打开", isOn: $settings.keepPanelOpen)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Text("⌥A 唤出面板 · ⌘⏎ 翻译 · ⌘⇧C 复制 · ⌘K 清空 · ⌘, 设置")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 划词

    private var selectionCard: some View {
        SettingsCard(title: "划词翻译") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("快捷键")
                        .font(.system(size: 12))
                        .frame(width: 78, alignment: .leading)
                    Picker("", selection: $settings.hotKeyPreset) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text("\(preset.title) 划词翻译").tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    Spacer()
                }

                Text("选中任意 App 里的文字，按快捷键即可翻译；浮窗里可一键替换原文。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Image(systemName: permissions.accessibilityGranted
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(permissions.accessibilityGranted ? .green : .orange)

                    Text(permissions.accessibilityGranted
                         ? "已获得辅助功能权限"
                         : "未获得辅助功能权限，划词功能不可用")
                        .font(.system(size: 12))

                    Spacer()

                    if !permissions.accessibilityGranted {
                        Button("去授权") {
                            permissions.requestAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("打开系统设置") {
                            permissions.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("权限状态会自动刷新；若仍不可用，请退出后重新打开墨译。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 关于

    private var aboutCard: some View {
        SettingsCard(title: "关于") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("墨译 1.10")
                        .font(.system(size: 12, weight: .semibold))
                    Text("原生 SwiftUI · 常驻菜单栏 · 数据只经过你自己的接口")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: 模型与密钥

    private func keyBinding(_ account: String) -> Binding<String> {
        Binding(
            get: { settings.apiKey(for: account) },
            set: { settings.setAPIKey($0, for: account) }
        )
    }

    private var draftKeyBinding: Binding<String> {
        Binding(get: { draftAPIKey }, set: { draftAPIKey = $0 })
    }

    private func isLocal(_ entry: ModelEntry) -> Bool {
        let account = entry.keyAccount
        return account.hasPrefix("localhost")
            || account.hasPrefix("127.0.0.1")
            || account.hasPrefix("[::1]")
    }

    private func endpointHint(_ entry: ModelEntry) -> some View {
        HStack(spacing: 10) {
            Text("Base URL")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(entry.baseURL)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func saveCustomModel() {
        guard let entry = settings.addCustomModel(
            name: draftName,
            baseURL: draftBaseURL,
            model: draftModel
        ) else { return }

        if !draftAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            settings.setAPIKey(draftAPIKey, for: entry.keyAccount)
        }
        settings.primaryEntryID = entry.id
        draftName = ""
        draftBaseURL = ""
        draftModel = ""
        draftAPIKey = ""
        selectedPresetID = ""
        saveHint = "已保存并设为主接口"
        testState = .idle
    }

    // MARK: 组件

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        secure: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 78, alignment: .leading)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var isTesting: Bool {
        if case .running = testState { return true }
        return false
    }

    private func runTest() {
        guard let entry = settings.primaryEntry else { return }
        testState = .running
        let config = TranslatorConfig(
            baseURL: entry.baseURL,
            apiKey: settings.apiKey(for: entry.keyAccount),
            model: entry.model,
            targetMode: settings.targetMode
        )
        Task {
            do {
                let result = try await Translator.translate(
                    "Hello, this is a connection test.",
                    config: config
                )
                await MainActor.run {
                    let preview = result.text.prefix(24)
                    testState = .success("连接正常 · \(preview)")
                }
            } catch {
                await MainActor.run {
                    testState = .failure(error.localizedDescription)
                }
            }
        }
    }
}

enum TestState {
    case idle
    case running
    case success(String)
    case failure(String)
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface()
    }
}
