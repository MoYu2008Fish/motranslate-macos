# Contributing / 参与开发

Bug reports and small, focused pull requests are welcome in English or Chinese. Please include your macOS version, app version, provider/model, and reproducible steps. Use synthetic example text, and never post API keys or private translations.

欢迎中文或英文反馈与 PR。请提供系统版本、应用版本、模型及复现步骤；用合成样例说明问题，不要上传密钥或私人译文。

## Development

Build with Xcode 26+ / its matching Command Line Tools on macOS. The app targets macOS 14+. The current UI is Simplified Chinese; English and Japanese README translations are documentation, not claims of a localized interface.

```sh
swift test
swift tools/deploy.swift --self-test
bash -n build.sh deploy.sh 'Deploy MoTranslate.command' 一键部署墨译.command
./build.sh release
```

`--self-test` uses temporary files and in-memory Dock samples. It does not install an app or modify your Dock. Running `deploy.sh` does modify your local installation, desktop alias, and the current user's Dock.

Model evaluations live in `benchmarks/`. Keep inputs synthetic, retain raw outputs, state hardware and settings, and distinguish warm inference from model-load time. Do not present a small local comparison as a universal leaderboard.

Before submitting a UI change, inspect the running app and update real screenshots when behavior changes. Before submitting a translation-engine change, cover stale-result cancellation and language routing with focused tests.

## Project layout

- `Sources/MoTranslate/`: AppKit lifecycle, SwiftUI panels, translation engine, selection/clipboard services.
- `Tests/MoTranslateTests/`: translation routing and async state tests.
- `Resources/`: icon artwork and packaged ICNS.
- `tools/`: icon packaging and installation helpers.
- `docs/`: usage, screenshots, and icon provenance.
- `benchmarks/`: reproducible local-model evaluation.

Contributions are provided under the repository's MIT license.
