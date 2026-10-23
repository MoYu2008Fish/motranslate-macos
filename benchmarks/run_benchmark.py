#!/usr/bin/env python3
"""Serial Ollama Chat Completions benchmark using Mo Translate's current prompt."""
import argparse, datetime, json, time, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SYSTEM = """You are a professional translator. Translate the user's text into {target}.
Rules:
- Output ONLY the translation. No explanations, prefixes, quotes, or notes.
- Preserve the original meaning, tone, formatting and line breaks.
- Keep proper nouns, code, URLs and technical terms accurate.
- If the text is already in {target}, return it unchanged."""

def request(base, model, case, timeout):
    body = {"model": model, "temperature": 0.2, "stream": False,
            "messages": [{"role":"system", "content": SYSTEM.format(target=case["target"])},
                         {"role":"user", "content":case["source"]}]}
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body, ensure_ascii=False).encode(), headers={"Content-Type":"application/json"}, method="POST")
    start=time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            data=json.load(response)
        text=data["choices"][0]["message"].get("content") or ""
        return {"output":text, "seconds":round(time.monotonic()-start,2), "error":None}
    except Exception as e:
        return {"output":"", "seconds":round(time.monotonic()-start,2), "error":f"{type(e).__name__}: {e}"}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--base", default="http://localhost:11434")
    p.add_argument("--timeout", type=int, default=75)
    p.add_argument("--models", nargs="+", required=True)
    p.add_argument("--output", default=str(ROOT/"results.json"))
    a=p.parse_args()
    cases=json.loads((ROOT/"cases.json").read_text())
    result={"created_at":datetime.datetime.now().astimezone().isoformat(),"base":a.base,"timeout_seconds":a.timeout,"prompt":"Mo Translate Translator.swift system prompt; temperature=0.2; stream=false","models":{}}
    for model in a.models:
        entries=[]
        print(f"MODEL {model}", flush=True)
        for case in cases:
            print(f"  {case['id']} ...", flush=True)
            res=request(a.base,model,case,a.timeout)
            entries.append({**case,**res})
            print(f"    {res['seconds']}s"+(f" ERROR {res['error']}" if res['error'] else ""),flush=True)
        result["models"][model]=entries
        Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    print(a.output)
if __name__=="__main__": main()
