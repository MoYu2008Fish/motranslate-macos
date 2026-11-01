import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

extension View {
    @ViewBuilder func glassControl() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }
    func contentSurface() -> some View {
        self.background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)))
    }
}

struct TranslateView: View {
    @ObservedObject var vm: TranslateViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsModel
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 18) {
            header
            languageBar
            GeometryReader { proxy in
                let layout = proxy.size.width >= 650
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                    : AnyLayout(VStackLayout(spacing: 14))
                layout {
                    inputCard
                    outputCard
                }
            }
            footer
        }
        .padding(22)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { VisualEffectBackground() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.18)))
        .tint(.accentColor)
        .onAppear { focusInput() }
        .onChange(of: vm.focusTick) { _, _ in focusInput() }
        .onChange(of: settings.targetMode) { _, _ in vm.targetChanged() }
        .onChange(of: settings.chunkingEnabled) { _, _ in vm.targetChanged() }
        .onChange(of: settings.streamingEnabled) { _, _ in vm.targetChanged() }
        .onChange(of: settings.style) { _, _ in vm.targetChanged() }
        .onChange(of: settings.markdownEnabled) { _, _ in vm.targetChanged() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("墨译").font(.system(size: 21, weight: .semibold))
                Text("让语言，自然流动").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                iconButton(settings.keepPanelOpen ? "pin.fill" : "pin", title: settings.keepPanelOpen ? "取消固定窗口" : "固定窗口，点击外部时保持打开") {
                    settings.keepPanelOpen.toggle()
                }
                iconButton("gearshape", title: "设置 · ⌘,") { onOpenSettings() }
                iconButton("xmark", title: "关闭 · esc") { onClose() }
            }
            .padding(5)
            .glassControl()
        }
    }

    private var languageBar: some View {
        HStack(spacing: 10) {
            Label("自动识别", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            Picker("目标语言", selection: $settings.targetMode) {
                ForEach(TargetMode.allCases) { mode in Text(mode == .auto ? "智能互译" : mode.shortTitle).tag(mode) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            Picker("翻译风格", selection: $settings.style) {
                ForEach(TranslationStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .help("翻译风格：自然、严谨、大白话、精简加总结")
            Spacer()
            modelMenu
            if settings.isManualModel {
                Button("恢复默认") {
                    settings.clearManualModel()
                    vm.targetChanged()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
                .help("恢复按峰谷规则自动切换模型")
            }
            if !permissions.accessibilityGranted {
                Button { permissions.openSystemSettings() } label: {
                    Label("开启划词", systemImage: "cursorarrow.click.2")
                }
                .buttonStyle(.borderless).font(.system(size: 11))
                .help("在系统设置中为墨译开启辅助功能权限")
            } else {
                Text("\(settings.hotKeyPreset.title) 划词").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    private var modelMenu: some View {
        Menu {
            if settings.library.isEmpty {
                Text("尚未配置模型")
            } else {
                ForEach(settings.library) { entry in
                    Button {
                        settings.selectModel(entry.id)
                        vm.targetChanged()
                    } label: {
                        if settings.activeEntry?.id == entry.id {
                            Label(entry.name, systemImage: "checkmark")
                        } else {
                            Text(entry.name)
                        }
                    }
                }
            }
            if settings.isManualModel {
                Divider()
                Button("恢复默认（自动切换）") {
                    settings.clearManualModel()
                    vm.targetChanged()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(settings.activeEntry?.name ?? "未配置模型")
                    .lineLimit(1)
                if settings.isManualModel {
                    Text("手动")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                }
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("临时切换模型，重启墨译后恢复默认")
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("原文").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { vm.pasteInput(); focusInput() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("粘贴剪贴板内容")
                Button { vm.reset(); focusInput() } label: { Image(systemName: "trash") }
                    .disabled(vm.input.isEmpty).help("清空 · ⌘K")
            }.buttonStyle(.borderless).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.input)
                    .font(.system(size: 16)).lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .onChange(of: vm.input) { _, _ in vm.inputChanged() }
                    .accessibilityLabel("要翻译的原文")
                if vm.input.isEmpty {
                    Text("输入或粘贴文字\n其余的，交给墨译。")
                        .font(.system(size: 16)).lineSpacing(6)
                        .foregroundStyle(.tertiary).padding(.top, 1).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text("\(vm.input.count) 字符").monospacedDigit()
                Spacer()
                Text(settings.autoTranslate ? "自动翻译已开启" : "⌘ return 翻译")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).contentSurface()
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("译文").font(.system(size: 12, weight: .semibold))
                Spacer()
                if vm.isWorking { ProgressView().controlSize(.mini) }
                Text(vm.directionLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let error = vm.errorText {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.system(size: 13)).foregroundStyle(.orange).textSelection(.enabled)
                            if !settings.isConfigured {
                                Button("配置翻译接口…", action: onOpenSettings).buttonStyle(.bordered)
                            } else { Button("重试") { vm.startTranslation() }.buttonStyle(.bordered) }
                        } else if vm.hasOutput {
                            Text(vm.output).font(.system(size: 16)).lineSpacing(6).textSelection(.enabled)
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "text.bubble").font(.system(size: 28, weight: .ultraLight))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(vm.isWorking ? (vm.progressText ?? "正在斟酌字句…") : "跨越语言，保留原意。")
                                        .font(.system(size: 14))
                                    Text(vm.isWorking ? "译文即将出现在这里" : "支持中英互译与多语言识别")
                                        .font(.system(size: 11))
                                }
                            }.foregroundStyle(.secondary).padding(.top, 8)
                        }
                        Color.clear.frame(height: 1).id("outputBottom")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.output) { _, _ in
                    // 流式/分段输出时跟随到底部，方便看到最新一段。
                    guard vm.isWorking else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("outputBottom", anchor: .bottom)
                    }
                }
            }
            HStack(spacing: 8) {
                if let progress = vm.progressValue {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .frame(width: 72)
                }
                Text(vm.progressText ?? (vm.isWorking ? "正在翻译" : vm.errorText != nil ? "翻译未完成" : vm.hasOutput ? "翻译完成" : "等待输入"))
                if !vm.activeModelLabel.isEmpty {
                    Text("· \(vm.activeModelLabel)").lineLimit(1)
                }
                Spacer()
                Button { vm.useOutputAsInput(); focusInput() } label: {
                    Label("用作原文", systemImage: "arrow.uturn.backward")
                }.buttonStyle(.borderless).disabled(!vm.hasOutput)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).contentSurface()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $settings.chunkingEnabled) {
                Text("分段").font(.system(size: 10))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("长文本按 Markdown 结构逐段翻译，边译边显示")
            Text("⌥ A 唤出  ·  esc 收起").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button { vm.copyOutput() } label: {
                Label(vm.copied ? "已复制" : "复制译文", systemImage: vm.copied ? "checkmark" : "doc.on.doc")
            }.buttonStyle(.bordered).disabled(!vm.hasOutput).help("⌘⇧C 复制译文")
            Button { vm.isWorking ? vm.cancelTranslation() : vm.startTranslation() } label: {
                Label(vm.isWorking ? "停止" : "翻译", systemImage: vm.isWorking ? "stop.fill" : "arrow.turn.down.left")
                    .frame(minWidth: 54)
            }.buttonStyle(.borderedProminent).disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("⌘ return 翻译")
        }.controlSize(.large)
    }

    private func iconButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 30).contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
    }
    private func focusInput() { DispatchQueue.main.async { inputFocused = true } }
}

struct PopupView: View {
    @ObservedObject var vm: TranslateViewModel
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble.fill").foregroundStyle(.tint)
                Text(vm.directionLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if vm.isWorking {
                    if let progress = vm.progressValue {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                            .frame(width: 46)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                if !vm.activeModelLabel.isEmpty {
                    Text(vm.activeModelLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help("关闭 · esc").accessibilityLabel("关闭划词浮窗")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = vm.errorText {
                        Text(error).foregroundStyle(.orange).font(.system(size: 13)).textSelection(.enabled)
                    } else {
                        Text(vm.output.isEmpty ? "正在斟酌字句…" : vm.output)
                            .font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    }
                    if !vm.input.isEmpty {
                        Divider()
                        Text(vm.input).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button { vm.copyOutput() } label: {
                    Label(vm.copied ? "已复制" : "复制", systemImage: vm.copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.bordered).disabled(!vm.hasOutput)
                Spacer()
                Button { vm.replaceBack() } label: {
                    Label(vm.replaced ? "已替换" : "替换原文", systemImage: "arrow.turn.down.left")
                }.buttonStyle(.borderedProminent).disabled(!vm.hasOutput || vm.replaced || vm.targetPID == nil)
            }.controlSize(.regular)
        }
        .padding(18).background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.2)))
    }
}
