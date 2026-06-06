#!/usr/bin/env python3
"""Fast model/provider switch for portable Hermes.

Updates the `model:` block in data/config.yaml and (optionally) upserts a key
into data/.env — without clobbering the rest of the config. Comment-preserving
when ruamel.yaml is available (it is, in the Hermes venv), else falls back to
PyYAML.

Usage:
  switch-model.py --config <config.yaml> --env <.env> \
      --provider <p> --model <m> [--base-url <url>] [--set-env KEY=VALUE]
  (pass --base-url "" to remove an existing base_url)
"""
import argparse
import sys
from pathlib import Path


def _load_dump():
    try:
        from ruamel.yaml import YAML
        y = YAML()
        y.preserve_quotes = True
        y.indent(mapping=2, sequence=4, offset=2)

        def load(p):
            txt = Path(p).read_text() if Path(p).exists() else ""
            return y.load(txt) or {}

        def dump(p, d):
            with open(p, "w") as f:
                y.dump(d, f)
        return load, dump
    except Exception:
        import yaml as pyyaml

        def load(p):
            txt = Path(p).read_text() if Path(p).exists() else ""
            return pyyaml.safe_load(txt) or {}

        def dump(p, d):
            Path(p).write_text(pyyaml.safe_dump(d, sort_keys=False))
        return load, dump


def set_env(env_path: str, key: str, val: str) -> None:
    p = Path(env_path)
    lines = p.read_text().splitlines() if p.exists() else []
    out, found = [], False
    for ln in lines:
        if ln.strip().startswith(key + "="):
            out.append(f"{key}={val}")
            found = True
        else:
            out.append(ln)
    if not found:
        out.append(f"{key}={val}")
    p.write_text("\n".join(out) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--env", required=True)
    ap.add_argument("--provider", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--base-url", default=None)
    ap.add_argument("--set-env", default=None, help="KEY=VALUE to upsert into .env")
    a = ap.parse_args()

    load, dump = _load_dump()
    cfg = load(a.config)
    if not isinstance(cfg, dict):
        cfg = {}
    model = cfg.get("model")
    if not isinstance(model, dict):
        model = {}
        cfg["model"] = model

    model["provider"] = a.provider
    model["default"] = a.model
    if a.base_url is not None:
        if a.base_url == "":
            model.pop("base_url", None)
        else:
            model["base_url"] = a.base_url
    dump(a.config, cfg)

    if a.set_env:
        if "=" not in a.set_env:
            print("--set-env must be KEY=VALUE", file=sys.stderr)
            return 2
        k, v = a.set_env.split("=", 1)
        set_env(a.env, k.strip(), v)

    print(f"OK  provider={a.provider}  model={a.model}"
          + (f"  base_url={a.base_url}" if a.base_url else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
