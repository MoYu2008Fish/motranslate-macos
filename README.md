<p align="center"><img src="Resources/AppIcon-preview.png" width="112" alt="MoTranslate app icon"></p>

# MoTranslate / 墨译 — Native macOS AI Translator

[简体中文](README.zh-CN.md) · **English** · [日本語](README.ja.md)

A lightweight **Mac menu-bar translator** built with SwiftUI and AppKit. Translate typed, pasted, or selected text with **local Ollama models** or a **Chat Completions-compatible API**. Keep a translation panel one shortcut away, compare source and result side by side, and copy the result back into your work.

**macOS 14+ · Apple Silicon release · SwiftUI / AppKit · MIT license**

<img src="docs/screenshots/01-translation.png" width="900" alt="Actual MoTranslate window showing a Chinese-to-English translation">

*Actual application screenshot using synthetic example text. Interface language: Simplified Chinese. English and Japanese documentation are available; they are not localized UI screenshots.*

## Why MoTranslate?

- **Local AI translation:** connect to Ollama on `localhost`; after downloading a local model, inference can run without a cloud translation service.
- **Selection translation:** select text in another app and press **⌥D**. A compact popup can copy the translation or replace the original selection in editable apps, subject to Accessibility support.
- **Fast keyboard workflow:** **⌥A** opens the panel, **⌘Return** translates, **⌘⇧C** copies, and **⌘K** clears.
- **Mac-native panels:** resizable side-by-side / stacked layouts, a pin toggle, multiple-display positioning, and system materials. macOS 26+ uses Liquid Glass controls; older supported systems use native material fallbacks.
- **Built-in catalog, your own library:** when adding a model, pick from an Ollama, DeepSeek, OpenAI, Anthropic, Gemini, Kimi, Zhipu, Qwen, SiliconFlow, or OpenRouter preset; the Base URL and model ID are filled in, so you usually only add an API key. The catalog was checked against [models.dev](https://models.dev) in 2026-10. Only models you add appear in the panel and peak/off-peak pickers.
- **Simple deployment:** one command builds, backs up the previous installation, creates a desktop Finder alias, pins one Dock entry, and launches the app.
- **Predictable request state:** 700 ms automatic-translation debounce, cancel / retry actions, and stale-result invalidation when text or target language changes.
- **Long text in chunks, Markdown rendered:** long input is split along Markdown structure, code blocks are left untouched, and paragraphs are translated serially. The result view renders headings, bold, italics, lists, quotes and code blocks instead of showing `**` markers. Toggle chunking in the panel at any time. Streaming is on by default and can be turned off for endpoints that do not support it. Markdown detection is on by default and can be disabled in Settings.
- **Translation style:** natural, precise, plain language, conversational, or concise with a summary. Switch directly in the panel and the text is re-translated.
- **Peak / off-peak model switching (off by default):** optionally use your local model during peak hours and a cloud model off-peak. Peak windows and weekend handling are editable. MoTranslate only follows the clock rules you configure; check your provider's own pricing schedule.

## Install

### Prebuilt app — Apple Silicon

1. Download `MoTranslate-macos-arm64.zip` from [Releases](https://github.com/MoYu2008Fish/motranslate-macos/releases).
2. Extract it and move `MoTranslate.app` to Applications. Open it, then choose Settings (**⌘,**).
3. Configure a local model or your own compatible endpoint. Models and provider credentials are not included.

The release is locally ad-hoc signed and **not notarized**. macOS may require you to review it before opening; follow your system's normal security prompts. Intel binaries are not provided in this release. macOS 14/15 and macOS 27 have not been runtime-tested; the current screenshots and local checks were made on macOS 26.

### Build and deploy from source

Requires **Xcode 26+ or matching Command Line Tools with the macOS 26+ SDK**. The app deployment target is macOS 14.

```sh
git clone https://github.com/MoYu2008Fish/motranslate-macos.git
cd motranslate-macos
./deploy.sh
```

Or double-click **`Deploy MoTranslate.command`** / **`一键部署墨译.command`** in Finder.

The installer updates `/Applications/MoTranslate.app`, creates `~/Desktop/墨译.app` as a Finder alias, and adds/updates one persistent Dock tile. It preserves other Dock applications and their order, briefly restarts your Dock to refresh the icon, and uses `~/Applications` only if `/Applications` is not writable and no installation already exists there. Run it as your desktop user, **without sudo**.

```sh
./build.sh release                    # Build only
./deploy.sh --no-build                # Install the already-built app
./deploy.sh --no-build --no-launch    # Install without opening it
```

Previous apps are backed up as ZIP archives along with the previous desktop alias and Dock app-list configuration under `~/Library/Application Support/MoTranslate/DeploymentBackups/`. Repeated deployment does not add duplicate Dock entries. A same-named unrelated desktop file causes deployment to stop instead of overwriting it.

## Configure Ollama or a remote API

<img src="docs/screenshots/03-local-model-settings.png" width="620" alt="Settings showing a local Ollama endpoint and a local model alias">

1. Start your local Ollama server and run `ollama list` to find the exact model tag installed on your machine.
2. Open **Settings → 翻译服务**. Set Base URL to `http://localhost:11434/v1`, leave API Key empty, and enter that model tag.
3. Click **测试连接** (Test connection), then close Settings and paste text into the main panel.

The screenshot uses a local alias (`qwen3-4b`); your model tag may differ. The Ollama preset is an editable example, not a model download or proof that the model is installed. See the [local-model benchmark](benchmarks/README.md) for the models tested on the development machine, raw outputs, timings, and limitations.

For a remote service, enter its compatible Base URL, exact model ID, and API key. The app appends `/chat/completions` to a URL ending in `/v1`, or `/v1/chat/completions` to a bare host. A full endpoint ending in `/chat/completions` is accepted unchanged. It does **not** implement arbitrary Responses-only or non-compatible APIs.

### Tested local models

On the development Mac (M1 Max, 64 GB), a 12-case synthetic comparison per model favored the installed **Qwen3-4B-Instruct-2507 Q4_K_M** variant (`qwen3-4b:latest`) for everyday use: mean response time **0.62 s**. Gemma4 26B was more polished in some cases but averaged **18.69 s**; 1.7B is a smaller fallback, and 0.6B showed meaning omissions. These are installed-configuration timings, including different model variants/backends, not a universal speed ranking. Quality was reviewed subjectively by Luna medium. See [full outputs and limitations](benchmarks/REPORT.md).

## Use it

1. Press **⌥A**, then type or paste your source text.
2. Leave automatic translation on, or press **⌘Return** / click **翻译**. Enter alone inserts a line break.
3. Select **智能互译** for automatic Chinese → English / other detected languages → Chinese, or choose a fixed Chinese or English target.
4. Click **复制译文** or press **⌘⇧C**. Use the pin button to keep the panel open while working elsewhere.

The current target choices are **Chinese and English**. Detection of other source languages is supported by the engine, but mixed scripts and very short inputs can be ambiguous. It is not an arbitrary-target multilingual translation UI.

| Action | Shortcut |
| --- | --- |
| Show / hide panel | ⌥A |
| Translate selection | ⌥D by default; configurable |
| Translate | ⌘Return |
| Copy translation | ⌘⇧C |
| Clear | ⌘K |
| Settings | ⌘, |
| Hide panel | Esc / ⌘W |

### Selection translation and permissions

<img src="docs/screenshots/04-shortcuts-permissions.png" width="620" alt="Actual shortcut and Accessibility permission settings">

Enable MoTranslate in **System Settings → Privacy & Security → Accessibility** for selection reading and replacement. Regular typed/pasted translation does not require Accessibility permission. Some apps expose neither readable nor editable selections; copy/paste fallbacks are best effort. You may need to re-add the app after rebuilding or moving it. The screenshot intentionally shows the permission-not-granted state; a cross-app replacement demonstration was not captured.

### Compact layout

<img src="docs/screenshots/02-compact-layout.png" width="540" alt="The same real translation window resized into a stacked layout">

Resize the panel by its edges. Narrow windows stack the source and translation vertically; wide windows show both side by side. The panel follows system light/dark appearance and Reduce Transparency settings.

## Privacy and troubleshooting

- Text goes to **your configured endpoint**. With a remote service, it leaves your machine. API keys live in Keychain; other preferences live in UserDefaults. See [SECURITY.md](SECURITY.md).
- **No translation?** Check the server, exact model ID, endpoint, and provider response in Test connection. Model downloads are separate from app installation.
- **Slow local inference?** First load may be slow. Loopback endpoints wait up to 180 seconds; remote requests use 60 seconds. Stop or retry from the panel, or choose a smaller model. Timings depend on hardware, quantization, context, and model behavior.
- **Shortcut does nothing?** Quit other copies of MoTranslate and resolve conflicts with your existing shortcuts. The main shortcut is fixed; the selection shortcut has presets.
- **Selection replacement fails?** Check Accessibility permission and whether the target app supports editable selections. The app cannot guarantee replacement in every application.

## Build, test, and contribute

```sh
swift test
swift tools/deploy.swift --self-test
./build.sh release
```

The helper self-test uses temporary aliases and in-memory Dock fixtures; it does not install the app or modify your Dock. CI builds the app on macOS 26. There are no external Swift package dependencies. [Contributions](CONTRIBUTING.md), issue reports, and documentation improvements are welcome.

[Model benchmark](benchmarks/README.md) · [Step-by-step guide / 操作指南](docs/usage.md) · [Icon artwork and generation prompt](docs/icon-design.md) · [MIT license](LICENSE)

**Search terms:** macOS translator, Mac translation app, menu bar translator, selection translation, clipboard translation, local AI, Ollama translator, offline translation, OpenAI-compatible API, Chinese English translation, SwiftUI, AppKit, Apple Silicon, Liquid Glass. 中文：Mac 翻译器、划词翻译、菜单栏翻译、剪贴板翻译、本地大模型、离线翻译、中英互译。
