# 操作指南 / Step-by-step guide

[中文说明](../README.zh-CN.md) · [English](../README.md) · [日本語](../README.ja.md)

这些截图来自实际运行的墨译 1.2，拍摄于 macOS 26。1.3 起新增的「峰谷调度」卡片默认折叠，1.4 起主面板增加了模型下拉与分段进度；其余界面与截图一致。内容使用合成示例；界面未经过重新绘制或模拟。设置页截图使用本地地址，没有公开 API 密钥。窗口左上角的紫色标识是拍摄期间的系统屏幕共享提示。

These are real MoTranslate 1.2 windows captured on macOS 26, using synthetic sample text. The 峰谷调度 card added in 1.3 is collapsed by default, and 1.4 added a model picker and chunk progress to the main panel; the rest of the interface matches the screenshots. Screens are not mockups. Settings show a local endpoint and no API secret. The purple indicator on the settings title bar is a system screen-sharing indicator during capture.

## 1. 输入并翻译 / Enter text and translate

按 ⌥A 唤出窗口，输入或粘贴文本。自动翻译开启时停止输入约 700ms 后发起请求；手动模式下按 ⌘Return。译文完成后点击「复制译文」或按 ⌘⇧C。目标语言旁可选择翻译风格：自然、严谨、大白话、口语、精简 + 总结，切换后会自动重译。长文本会按 Markdown 结构分段串行翻译，代码块原样保留；面板底部可以随时开关「分段」，开启时译文会一段一段出现。流式输出默认开启，译文边生成边显示，不支持流式的接口可在设置里关闭。Markdown 识别默认开启，可在设置里关闭。面板底部同时显示分段进度和本次使用的模型。顶部的模型下拉可临时切换主接口或谷时接口；手动选择只保留到本次运行结束，点「恢复默认」或重启墨译即回到峰谷自动规则。

Press ⌥A, enter or paste text, then wait for automatic translation or press ⌘Return. Use 复制译文 / ⌘⇧C to copy the result. Enter without Command inserts a new line. Pick a translation style next to the target language — natural, precise, plain language, conversational, or concise with a summary — and the text is re-translated automatically. Long input is split along Markdown structure and translated paragraph by paragraph with code blocks kept as-is; the 分段 toggle at the bottom can be switched at any time, and results appear one paragraph at a time. Streaming is on by default so text appears as it is generated; disable it in Settings for endpoints without streaming support. Markdown detection is on by default and can be disabled in Settings. The footer also shows chunk progress and the model used. The model menu at the top temporarily switches between the main and off-peak endpoints for this run only; choose 恢复默认 or restart the app to return to the peak/off-peak rule.

![真实中译英界面 / Actual translation window](screenshots/01-translation.png)

## 2. 配置模型 / Configure a model

按 ⌘, 打开「翻译服务」。「主接口」下拉只列出你已经添加过的模型。要新增模型，到下面的「自有模型库」：从预设选择服务商与模型（内置 Ollama、DeepSeek、OpenAI、Anthropic、Gemini、Kimi、智谱、通义、硅基流动、OpenRouter，目录核对自 models.dev），Base URL 与模型代号会自动填好，通常只需补 API Key，然后点「保存到模型库」，它会设为主接口并出现在所有下拉里。点击「测试连接」会向主接口发送一条合成英文测试句。API Key 按服务商保存在系统钥匙串，同一服务商的多个模型共用一份。

Press ⌘, and open 翻译服务. The 主接口 picker only lists models you have added. To add one, use 自有模型库: pick a preset (Ollama, DeepSeek, OpenAI, Anthropic, Gemini, Kimi, Zhipu, Qwen, SiliconFlow, OpenRouter; catalog checked against models.dev), and the Base URL and model ID are filled in. Add the provider's API key if needed, press 保存到模型库, and it becomes the main endpoint and appears in every picker. 测试连接 sends a synthetic English test sentence to the main endpoint. API keys are stored per provider in the macOS Keychain, so models from the same provider share one key.

再往下是「峰谷调度」：默认关闭。开启后，高峰时段使用上面的主接口，其余时间改用谷时接口；高峰时段和周末规则可编辑，按本机时区判断。中国法定节假日无法自动识别，需要时请临时关闭调度。DeepSeek 官方高峰为工作日 9:00–12:00、14:00–18:00。

Further down is 峰谷调度, off by default. When enabled, peak hours use the main endpoint above and other hours use the off-peak endpoint. Peak windows and weekend handling are editable and evaluated in the local time zone. Chinese statutory holidays are not detected automatically; disable the schedule for those days if needed. DeepSeek's official peak hours are weekdays 9:00–12:00 and 14:00–18:00 Beijing time.

![实际模型配置 / Actual local-model configuration](screenshots/03-local-model-settings.png)

## 3. 快捷键与划词权限 / Shortcuts and selection permission

打开「通用与快捷键」。可关闭自动翻译或自动读取剪贴板，也可设置窗口固定和划词快捷键。跨应用划词前，需要手动在系统设置中授予辅助功能权限；此截图记录的是未授权状态，不能作为替换原文成功的证明。

Open 通用与快捷键 to configure automatic translation, clipboard filling, pinning, and the selection shortcut. Grant Accessibility access yourself in System Settings before using cross-app selection translation. This screenshot shows the permission-not-granted state, not a verified successful replacement.

![快捷键与未授权提示 / Shortcuts and permission state](screenshots/04-shortcuts-permissions.png)

## 4. 调整窗口 / Resize the window

拖动窗口边缘，宽窗口左右排列，窄窗口上下排列。右上角图钉控制点击其他应用时是否保留窗口，Esc 可收起。

Drag a window edge to resize it. The source and result stack vertically when narrow and appear side by side when wide. The pin keeps the window open when you click another app; Esc hides it.

![实际窄屏布局 / Actual compact layout](screenshots/02-compact-layout.png)

## 5. 一键部署 / One-command deployment

克隆仓库后双击 `一键部署墨译.command` / `Deploy MoTranslate.command`，或运行 `./deploy.sh`。此操作会更新应用、创建桌面替身并固定 Dock；旧版及相关配置会先备份。不要使用 sudo。源码部署需要对应的 Xcode / Command Line Tools；只运行 Releases 的应用不需要编译工具。

After cloning, double-click either command file or run `./deploy.sh`. It updates the app, creates a desktop Finder alias, and pins one Dock tile, backing up the previous app and related configuration. Do not use sudo. Source deployment needs Xcode / Command Line Tools; running a prebuilt release app does not.
