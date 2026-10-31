import SwiftUI
import AppKit

// MARK: - 设置窗口

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsModel
    var onClose: () -> Void

    @State private var revealKey = false
    @State private var testState: TestState = .idle

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
                settingsPage { apiCard; scheduleCard }.tabItem { Label("翻译服务", systemImage: "network") }
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
                HStack(spacing: 6) {
                    Text("快速填入")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(Preset.all) { preset in
                        Button(preset.name) {
                            settings.baseURL = preset.baseURL
                            settings.model = preset.model
                            testState = .idle
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.bottom, 2)

                labeledField("Base URL", text: $settings.baseURL,
                             placeholder: "https://api.openai.com/v1")
                labeledField("API Key", text: $settings.apiKey,
                             placeholder: "sk-…（本地模型可留空）", secure: !revealKey)
                labeledField("模型", text: $settings.model,
                             placeholder: "gpt-4o-mini")

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

                    labeledField("Base URL", text: $settings.offPeakBaseURL,
                                 placeholder: "https://api.deepseek.com/v1")
                    labeledField("API Key", text: $settings.offPeakAPIKey,
                                 placeholder: "sk-…（本地模型可留空）", secure: !revealKey)
                    labeledField("模型", text: $settings.offPeakModel,
                                 placeholder: "deepseek-chat")

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
                    Text("墨译 1.4")
                        .font(.system(size: 12, weight: .semibold))
                    Text("原生 SwiftUI · 常驻菜单栏 · 数据只经过你自己的接口")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
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
        testState = .running
        let config = settings.config
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

struct Preset: Identifiable {
    let id = UUID()
    let name: String
    let baseURL: String
    let model: String

    static let all: [Preset] = [
        Preset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        Preset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        Preset(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-7B-Instruct"),
        Preset(name: "Ollama", baseURL: "http://localhost:11434/v1", model: "qwen2.5:7b")
    ]
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
