import argparse
import json
import os
import sqlite3
import tempfile
from contextlib import closing
from urllib.error import HTTPError
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .model import deduplicate, matches, normalize, now
from .providers import REGISTRY


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    os.replace(temp, path)


def generate(root, output=None, timestamp=None, registry=None):
    root = Path(root)
    output = Path(output) if output else root / "public"
    registry = registry if registry is not None else REGISTRY
    timestamp = timestamp or now()
    config = read_json(root / "config/providers.json")
    search_config = read_json(root / "config/searches.json")
    searches = search_config["searches"]
    state_file = root / "data/state.json"
    previous = read_json(state_file) if state_file.exists() else {"listings": [], "lastSuccessfulFetch": None}
    cutoff = (datetime.fromisoformat(timestamp.replace("Z", "+00:00")) - timedelta(days=search_config.get("retentionDays", 90))).isoformat(timespec="seconds").replace("+00:00", "Z")
    statuses = []
    successful_fetch = False
    with tempfile.TemporaryDirectory(prefix="immoflux-") as temp:
        with closing(sqlite3.connect(str(Path(temp) / "listings.sqlite"))) as db:
            db.execute("CREATE TABLE listings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            for item in previous["listings"]:
                if item["lastSeenDate"] >= cutoff:
                    db.execute("INSERT OR REPLACE INTO listings VALUES (?, ?)", (item["id"], json.dumps(item)))
            for key, provider in registry.items():
                settings = config.get(key, {})
                status = {"id": key, "name": provider.NAME, "enabled": bool(settings.get("enabled")),
                          "status": "disabled", "message": provider.REASON, "lastRun": timestamp, "count": 0,
                          "lastSuccess": None}
                old_dates = [x["lastSeenDate"] for x in previous["listings"] if x["source"] == key]
                if old_dates:
                    status["lastSuccess"] = max(old_dates)
                if settings.get("enabled"):
                    if not hasattr(provider, "fetch"):
                        status["status"] = "unavailable"
                    else:
                        try:
                            raw = provider.fetch(settings)
                            normalized = [normalize(x, key, timestamp) for x in raw]
                            items = [x for x in normalized if any(matches(x, s) for s in searches)]
                            # Fail the whole provider on invalid input: never partially overwrite its history.
                            with db:
                                for item in items:
                                    row = db.execute("SELECT payload FROM listings WHERE id = ?", (item["id"],)).fetchone()
                                    old = json.loads(row[0]) if row else None
                                    history = list(old.get("priceHistory", [])) if old else []
                                    if old:
                                        item["firstSeenDate"] = old["firstSeenDate"]
                                        for field in ("previousPrice", "priceChange", "priceChangedAt"):
                                            item[field] = old.get(field)
                                        if item["price"] is None:
                                            item["price"] = old["price"]
                                        elif old["price"] is not None and old["price"] != item["price"]:
                                            item["previousPrice"] = old["price"]
                                            item["priceChange"] = round(item["price"] - old["price"], 2)
                                            item["priceChangedAt"] = timestamp
                                    if item["price"] is not None and (not history or history[-1]["price"] != item["price"]):
                                        history.append({"date": timestamp, "price": item["price"]})
                                    item["priceHistory"] = history[-30:]
                                    item["pricePerSquareMeter"] = round(item["price"] / item["surface"], 2) if item["price"] is not None and item["surface"] else None
                                    db.execute("INSERT OR REPLACE INTO listings VALUES (?, ?)", (item["id"], json.dumps(item)))
                            successful_fetch = True
                            warning = getattr(raw, "warning", None)
                            status.update(status="partial" if warning else "ok", message=warning or "Flux récupéré et validé.", count=len(items), lastSuccess=timestamp)
                        except Exception as exc:
                            # Deliberately avoid logging upstream response bodies / credentials / private payloads.
                            kind = f"HTTP {exc.code}" if isinstance(exc, HTTPError) else type(exc).__name__
                            status.update(status="error", message=f"Échec de collecte ({kind}). Dernières données conservées.")
                statuses.append(status)
                print(f"{key}: {status['status']} ({status['count']} annonces)")
            items = [json.loads(row[0]) for row in db.execute("SELECT payload FROM listings")]
    items = sorted(items, key=lambda x: x["lastSeenDate"], reverse=True)[:min(search_config.get("maxListings", 2000), 5000)]
    last_success = timestamp if successful_fetch else previous.get("lastSuccessfulFetch")
    write_json(state_file, {"schemaVersion": 1, "lastSuccessfulFetch": last_success, "listings": items})
    enabled_ids = {s["id"] for s in statuses if s["enabled"] and s["status"] in ("ok", "partial", "error")}
    public_items = [x for x in items if x["source"] in enabled_ids and any(matches(x, s) for s in searches)]
    listings = deduplicate(public_items)
    common = {"schemaVersion": 1, "generatedAt": timestamp}
    write_json(output / "listings.json", {**common, "lastSuccessfulFetch": last_success, "coverage": searches, "listings": listings})
    write_json(output / "providers.json", {**common, "providers": statuses})
    write_json(output / "stats.json", {**common, "total": len(listings), "beforeDeduplication": len(public_items),
                                       "priceDrops": sum(1 for x in listings if (x.get("priceChange") or 0) < 0)})
    health = "ok" if statuses and all(s["status"] in ("ok", "disabled") for s in statuses) and successful_fetch else "degraded"
    write_json(output / "health.json", {**common, "status": health, "lastWorkflowRun": timestamp,
                                        "lastSuccessfulFetch": last_success, "activeProviders": sum(s["status"] == "ok" for s in statuses)})
    output.mkdir(parents=True, exist_ok=True)
    (output / ".nojekyll").touch()
    summary = f"## ImmoFlux\n\nGénération : {timestamp}\n\n{len(listings)} annonces, état : {health}.\n\n" + "\n".join(f"- {s['name']} : {s['status']} ({s['count']})" for s in statuses)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(summary + "\n")
    return listings, statuses


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--output")
    args = parser.parse_args()
    generate(args.root, args.output)
