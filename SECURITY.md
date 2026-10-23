# Security and privacy

MoTranslate sends the text you submit to the endpoint configured in Settings. With a local Ollama endpoint and a downloaded local model, translation inference can stay on your Mac. A remote endpoint receives the text and any configured authentication header; its operator's policy applies.

API keys are stored in the macOS Keychain. Endpoint, model, and behavior settings use UserDefaults. The app does not implement a translation-history database, account service, or analytics collector. Your model provider may independently retain requests or logs.

Accessibility access is used to read selected text from other applications and optionally replace it. When direct selection access is unavailable, the app falls back to simulated copy/paste and attempts to restore the clipboard. Clipboard restoration is best effort: applications and clipboard managers may behave differently. Avoid translating sensitive text through an endpoint you do not trust.

The source installer backs up the existing app, desktop alias, and Dock app-list settings. Deployments do not intentionally change API keys or translation preferences. Locally built/released apps are ad-hoc signed, not Developer ID notarized. No script disables Gatekeeper, SIP, or other macOS security protections.

Do not put API keys, private documents, or unredacted credentials in public issues. For a suspected security issue, first use GitHub private vulnerability reporting if available; otherwise open a minimal issue requesting a private contact channel without disclosing exploit details or secrets.
