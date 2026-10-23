# 墨译本地 Ollama 翻译模型小测

日期：2026-10-23

## 结论 / Summary

**推荐默认使用 `qwen3-4b:latest`。** 在这组 12 条中英双向合成句上，它的忠实度和可读性整体较好，平均耗时 0.62 秒（中位数 0.56 秒），是质量与响应速度最均衡的候选。`gemma4:26b` 的译文整体最稳、格式保留也好，但平均耗时 18.69 秒，中位数 15.61 秒，慢句达到 52.31 秒；适合作为可接受等待时的质量优先选项，不建议作为日常默认。

轻量备选可选 `qwen3-1.7b:latest`，但其译文质量弱于 4B。它的模板含有 `enable_thinking=false` 条件分支，墨译当前请求没有设置该项；可以在应用侧增加选项后再做同接口对照。`qwen3-0.6b:latest` 虽小，出现了技术信息遗漏和短句生硬等问题，不建议用于需要可靠含义的常规翻译。

**English summary:** `qwen3-4b:latest` is the best default in this small test: strong overall quality at 0.62 s mean latency. `gemma4:26b` was slightly more polished but much slower (18.69 s mean, up to 52.31 s). `qwen3-1.7b:latest` is a possible smaller fallback, though its quality was weaker. Its template has an `enable_thinking=false` branch, but the app does not set that option. The 0.6B model made meaning errors that make it hard to recommend for general use.

## 测试方法

- 只读查看墨译 `Translator.swift` 与 `Settings.swift`；请求按项目使用的 OpenAI 兼容 `/v1/chat/completions` 接口发送。
- system prompt 与 `Translator.swift` 一致；`temperature=0.2`、`stream=false`，不传其他生成参数，也不传 API key。只提交 `cases.json` 中的合成短句。
- 语料共 12 条，覆盖中英双向、口语、技术、歧义、格式保留、短句和自然表达。用例文本及参考译法均为合成数据；参考译法用于说明意图，不作为正式 gold 标准。
- 串行调用，不并发占用本地推理；每请求超时 75 秒。共 48 次主测请求，均成功，无空响应、错误或超时。
- 质量分是 Luna medium 对本组样本输出的主观评审，采用 1–5 整数分；这不是人工盲评、多人一致性评审或自动指标，也不能视作普适模型排名。速度是各自 12 条的实测均值/中位数，包含模型切换和运行状态影响，不能当作稳定吞吐承诺。

## 本机可用候选

以下版本、量化格式与 runner 取自本次 `/api/tags` 与 `/api/show`；体积是本地模型文件大小，不代表精确运行内存。

| Ollama 模型 | API 模型标识 | 参数量 / 量化 / runner | 本地文件大小 | 结论 |
|---|---|---:|---:|---|
| `qwen3-0.6b:latest` | Qwen3-0.6B | 596M / Q4_K_M / llama.cpp | 0.40 GB | 最小，但有信息遗漏 |
| `qwen3-1.7b:latest` | Qwen3-1.7B | 1.7B / Q4_K_M / llama.cpp | 1.11 GB | 可作轻量备选 |
| `qwen3-4b:latest` | Qwen3-4B-Instruct-2507 | 4.0B / Q4_K_M / llama.cpp | 2.50 GB | 推荐默认 |
| `gemma4:26b` | Gemma4 | 26.2B / NVFP4 / MLX | 16.15 GB | 质量优先选项，响应慢 |

本次模型 digest、标签元数据、`/api/show` 参数和 thinking/template 证据见 [metadata.json](metadata.json)。`qwen3-4b:latest` 这个本地 alias 的模型标识是 **Qwen3-4B-Instruct-2507**，不是仅由 `4B` 参数量描述的同一模型系列配置。它已存参数只有 `num_ctx=4096` 和 `temperature=0.2`，`thinking` 字段为空，模板没有检测到 `enable_thinking=false` 分支；0.6B 与 1.7B 模板则含此分支。Gemma4 的 NVFP4 与 MLX 信息来自 `/api/show.details`；`/api/tags` 本身没有填 quantization 字段。不同模型变体、模板、量化和 runner 都可能影响速度与输出，因此 4B 的低延迟不能单独归因于模型大小或能力，也没有证据证明其 Ollama 参数显式关闭了 thinking。

设备为 Apple M1 Max、64 GB 统一内存，因此已安装的 26B 模型也可完成测试。Qwen 使用 llama.cpp，Gemma4 使用 MLX；不同运行后端也是比较限制之一。模型列表中没有 embedding-only 模型；本次没有下载或修改任何模型、应用配置或主程序代码。

## 结果概览

Luna medium 主观评分 1–5 整数，越高越好；没有计算综合均分，以免让小样本主观判断显得过于精确。

| 模型 | 含义忠实 | 中文/英文自然度 | 格式保留 | 只输出译文 | 平均耗时 | 中位耗时 |
|---|---:|---:|---:|---:|---:|---:|
| `qwen3-0.6b:latest` | 3 | 3 | 4 | 5 | 1.53 s | 1.58 s |
| `qwen3-1.7b:latest` | 4 | 4 | 5 | 5 | 2.48 s | 2.15 s |
| `qwen3-4b:latest` | 5 | 4 | 5 | 5 | 0.62 s | 0.56 s |
| `gemma4:26b` | 5 | 5 | 5 | 4 | 18.69 s | 15.61 s |

评分解释：0.6B 将 “cache miss” 技术句里的回退数据库语义误成重试，也把 “Works for me” 译得生硬；1.7B 能保留清单格式，但把 `idempotent`、`payment capture` 译成不自然术语；4B 对大多数句子表达准确，格式和术语保留较稳，个别中文技术搭配略生硬；26B 译文最自然，能较好保留代码、URL 和列表。`I saw her duck` 刻意保留歧义；“我看见她的鸭子”和“我看到她躲闪/躲开”是两种合理读法，选择其中一种不扣含义忠实分。Gemma 给出两个备选译法只影响“只输出译文”这一项。

## Qwen3 思考模式诊断

Ollama 标签对三款 Qwen 都列出 `thinking` capability。项目现有请求只发送温度、流式开关和消息，不显式设置 `think`，所以主测反映的是当前应用行为；主测三款 Qwen 都有非空译文，也没有把思考过程泄漏进 `content`。不过三款模型的标签、模板和模型变体不相同，不能把延迟差异单独归因于模型大小。

另用 Ollama 原生 `/api/chat` 对同一条中文技术句串行做了 `think=false` 单句诊断，精确请求对象、响应体和计时保存在 [diagnostics.json](diagnostics.json)。本次单句耗时为 0.6B 1.085 秒、1.7B 0.212 秒、4B 1.374 秒。它与主测所用 `/v1/chat/completions` 不同，模型运行状态也不同，因此不作直接速度对照。单条诊断不能证明关闭 thinking 会稳定加速；它只记录该开关在原生 API 上可用且返回非空译文。`qwen3-4b` 的模板检查没有找到 0.6B/1.7B 所见的 thinking 关闭分支，应用若要改变行为需先针对该模型验证可用接口。

## 可复现文件

- `cases.json`：合成测试集及意图参考译法。
- `run_benchmark.py`：串行调用脚本，默认 75 秒单请求超时；示例：

  ```sh
  python3 benchmarks/run_benchmark.py \
    --models qwen3-0.6b:latest qwen3-1.7b:latest qwen3-4b:latest gemma4:26b \
    --timeout 75
  ```

- `results.json`：本轮逐条原始结果、请求耗时与错误字段。
- `metadata.json`：模型 digest、Ollama 参数及模板/思考模式元数据。
- `diagnostics.json`：单句 `think=false` 诊断的原始响应数据。
