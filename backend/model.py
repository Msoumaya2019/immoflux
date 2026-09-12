import hashlib
import math
import re
import unicodedata
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def folded(value):
    return " ".join("".join(c for c in unicodedata.normalize("NFKD", str(value or "").lower())
                            if not unicodedata.combining(c)).split())


def public_url(value):
    if not isinstance(value, str):
        return None
    p = urlsplit(value)
    if p.scheme != "https" or not p.hostname or p.username or p.password or p.query or p.fragment:
        return None
    return urlunsplit(("https", p.netloc, p.path, "", ""))


def number(value, integer=False):
    if value is None or isinstance(value, bool):
        return None
    try:
        n = float(value)
        if not math.isfinite(n) or n < 0 or (integer and not n.is_integer()):
            return None
        return int(n) if integer else n
    except (ValueError, TypeError):
        return None


def normalize(raw, source, timestamp):
    sid = str(raw.get("sourceListingId", "")).strip()
    url = public_url(raw.get("url"))
    title = str(raw.get("title", "")).strip()
    city = str(raw.get("city", "")).strip()
    postal = str(raw.get("postalCode", "")).strip()
    if not sid or len(sid) > 160 or not url or not title or not city or not re.fullmatch(r"\d{5}", postal):
        raise ValueError("Missing ID, HTTPS URL without query, title, city or five-digit postal code")
    kind = {"maison": "house", "appartement": "apartment", "pavillon": "pavilion"}.get(raw.get("propertyType"), raw.get("propertyType"))
    transaction = {"vente": "sale", "location": "rent"}.get(raw.get("transactionType"), raw.get("transactionType"))
    if kind not in {"house", "apartment", "pavilion"} or transaction not in {"sale", "rent"}:
        raise ValueError("Unsupported property or transaction type")
    item = {"id": hashlib.sha256(f"{source}:{sid}".encode()).hexdigest()[:24],
            "source": source, "sourceListingId": sid, "title": title[:300], "url": url,
            "city": city[:100], "postalCode": postal, "propertyType": kind, "transactionType": transaction,
            "firstSeenDate": timestamp, "lastSeenDate": timestamp, "publicationDate": None,
            "previousPrice": None, "priceChange": None, "priceChangedAt": None,
            "isFavorite": False, "isHidden": False}
    for key in ("price", "surface", "landSurface", "rooms", "bedrooms"):
        item[key] = number(raw.get(key), key in ("rooms", "bedrooms"))
    for key, limit in (("latitude", 90), ("longitude", 180)):
        try:
            n = float(raw[key])
            item[key] = n if math.isfinite(n) and abs(n) <= limit else None
        except (KeyError, ValueError, TypeError):
            item[key] = None
    for key, limit in (("description", 20000), ("agency", 200)):
        item[key] = str(raw.get(key) or "")[:limit]
    images = raw.get("imageUrls") or []
    if not isinstance(images, list):
        raise ValueError("imageUrls must be an array")
    images = [raw.get("imageUrl")] + images
    item["imageUrls"] = list(dict.fromkeys(u for v in images if (u := public_url(v))))[:20]
    item["imageUrl"] = next(iter(item["imageUrls"]), None)
    if raw.get("publicationDate"):
        try:
            date = datetime.fromisoformat(raw["publicationDate"].replace("Z", "+00:00"))
            if date.tzinfo:
                item["publicationDate"] = date.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        except (ValueError, TypeError):
            pass
    item["pricePerSquareMeter"] = round(item["price"] / item["surface"], 2) if item["price"] is not None and item["surface"] else None
    item["priceHistory"] = []
    return item


def matches(item, search):
    return (folded(item["city"]) == folded(search["city"])
            and (not search.get("postalCode") or item["postalCode"] == search["postalCode"])
            and item["transactionType"] == search.get("transactionType", "sale")
            and (item["rooms"] or 0) >= search.get("minRooms", 0))


def same_home(a, b):
    # Conservative: price/area/title alone would merge unrelated flats in one building.
    if a["id"] == b["id"]:
        return True
    if a["source"] == b["source"] or any(a[k] != b[k] for k in ("postalCode", "transactionType")):
        return False
    if folded(a["city"]) != folded(b["city"]) or a["propertyType"] != b["propertyType"]:
        return False
    if not a["surface"] or not b["surface"] or abs(a["surface"] - b["surface"]) > 1 or a["rooms"] != b["rooms"]:
        return False
    if not a["price"] or not b["price"] or abs(a["price"] - b["price"]) / max(a["price"], b["price"]) > .03:
        return False
    photo_match = bool(set(a["imageUrls"]) & set(b["imageUrls"]))
    description_match = len(a["description"]) >= 120 and folded(a["description"]) == folded(b["description"])
    agency_match = bool(a["agency"]) and folded(a["agency"]) == folded(b["agency"])
    title_match = folded(a["title"]) == folded(b["title"])
    return photo_match or (description_match and agency_match and title_match)


def deduplicate(items):
    groups = []
    # Earliest detected ID is the stable canonical ID. All IDs retained for local favorites.
    for item in sorted(items, key=lambda x: (x["firstSeenDate"], x["id"])):
        group = next((g for g in groups if all(same_home(item, member) for member in g)), None)
        if group is None:
            groups.append([item])
        else:
            group.append(item)
    result = []
    for group in groups:
        newest = max(group, key=lambda x: (x["lastSeenDate"], x["id"]))
        listing = dict(newest)
        listing["id"] = group[0]["id"]
        listing["firstSeenDate"] = group[0]["firstSeenDate"]
        listing["memberIds"] = sorted({x["id"] for x in group})
        listing["sources"] = [{"source": x["source"], "url": x["url"], "sourceListingId": x["sourceListingId"]} for x in group]
        result.append(listing)
    return sorted(result, key=lambda x: x["firstSeenDate"], reverse=True)
