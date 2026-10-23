# Mo Translate local model benchmark / 墨译本地模型评测

**中文：** 从 [评测报告](REPORT.md) 开始，查看结论、测试范围、评分说明和局限。逐条合成样例及结果在 [cases.json](cases.json) 与 [results.json](results.json)；Ollama 模型 digest、参数和模板元数据见 [metadata.json](metadata.json)，单句 `think=false` 原生 API 诊断见 [diagnostics.json](diagnostics.json)。

**English:** Start with the [benchmark report](REPORT.md) for the recommendations, scope, scoring method, and limitations. Synthetic cases and per-model outputs are in [cases.json](cases.json) and [results.json](results.json). Ollama model digests, parameters, and template metadata are in [metadata.json](metadata.json); the single-case native API `think=false` diagnostic is in [diagnostics.json](diagnostics.json).

Re-run the primary comparison serially against the local Ollama service with:

```sh
python3 benchmarks/run_benchmark.py \
  --models qwen3-0.6b:latest qwen3-1.7b:latest qwen3-4b:latest gemma4:26b \
  --timeout 75
```

The report scores are Luna medium's subjective assessment of this small synthetic set, not a human blind review or a general model ranking. Model digests identify the artifacts captured for that run; results may differ with other model versions, templates, Ollama versions, and machine load.
