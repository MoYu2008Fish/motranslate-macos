# 墨译图标

内置 ImageGen 生成。采用无文字、扁平的相向对话形状，以负空间表达语言交流。

参考：[Apple Human Interface Guidelines — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/)。重点采用少量形状、居中主体、简单背景、小尺寸辨识度及避免非必要文字。官方规范允许平面图稿；现代 Icon Composer 输入不应预先裁切圆角。

文件：

- `Resources/AppIcon-source.png`：生成原稿，方形、未裁切。
- `Resources/AppIcon-preview.png`：1024 px macOS ICNS 外观预览。
- `Resources/AppIcon.icns`：实际打包到应用的多尺寸图标。
- `Resources/AppIcon-legacy.icns`：可选的本地旧图标备份，不随仓库发布。

生成提示词（内置 ImageGen，无参考图）：

```text
Use case: logo-brand. Asset type: actual app-icon artwork for MoTranslate, a minimal native translation utility. Follow Apple Human Interface Guidelines: one simple memorable concept, few bold filled shapes, balanced centered content, strong legibility at 24px, generous breathing room, no text. Design an ORIGINAL flat symbol showing two opposing, interlocking speech shapes that communicate language exchange: a white rounded speech shape toward upper-left and a pale sky-blue rounded speech shape toward lower-right, their speech tails pointing in opposite directions and a crisp narrow blue negative-space gap separating them. Together they form one compact balanced mark, elegant and distinctive rather than a generic chat notification icon. Use only solid cobalt blue (#2563EB) for the background, white, and pale sky-blue for the mark; absolutely flat fills. Main mark occupies about 58 percent of the square canvas. Full-bleed opaque cobalt-blue SQUARE background, edge to edge; NO rounded outer corners, NO outer margins, system mask will be applied later. 1024x1024 square image. No letters, no Chinese characters, no glyphs, no words, no arrows added outside the mark, no dots, no gradients, no translucency, no glass, no bevel, no texture, no shadows, no lighting, no perspective, no outlines, no 3D. Deliver one finished clean icon image, not a presentation or mockup.
```
