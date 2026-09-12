"""Run locally only. Does not output payloads, headers, or credentials."""
import json
import sys
from backend.providers import REGISTRY
from backend.model import normalize, now

name = sys.argv[1]
settings = json.load(open("config/providers.json", encoding="utf-8"))[name]
try:
    items = REGISTRY[name].fetch(settings)
    normalized = [normalize(x, name, now()) for x in items]
    print(f"{name}: {len(normalized)} valid listings")
except Exception as error:
    print(f"{name}: {type(error).__name__}: {error}")
    raise SystemExit(1)
