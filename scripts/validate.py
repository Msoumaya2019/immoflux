"""Validate public API contract, configuration and basic repository hygiene offline."""
import json
from datetime import datetime
from pathlib import Path
from backend.model import public_url


def validate(root=Path(".")):
    root = Path(root)
    for file in [*root.glob("config/*.json"), *root.glob("public/*.json"), root / "data/state.json"]:
        json.loads(file.read_text(encoding="utf-8"), parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON")))
    envelope = json.loads((root / "public/listings.json").read_text(encoding="utf-8"))
    assert envelope["schemaVersion"] == 1
    datetime.fromisoformat(envelope["generatedAt"].replace("Z", "+00:00"))
    required = {"id", "source", "sourceListingId", "title", "url", "imageUrls", "price", "surface", "rooms", "bedrooms", "landSurface",
                "propertyType", "transactionType", "city", "postalCode", "description", "agency", "firstSeenDate", "lastSeenDate",
                "publicationDate", "priceHistory", "priceChange", "previousPrice", "pricePerSquareMeter", "sources", "memberIds", "isFavorite", "isHidden"}
    ids = set()
    for item in envelope["listings"]:
        assert required <= item.keys(), f"Missing listing fields: {required - item.keys()}"
        assert item["id"] not in ids; ids.add(item["id"])
        assert public_url(item["url"])
        assert item["isFavorite"] is False and item["isHidden"] is False
        for key in ("firstSeenDate", "lastSeenDate"):
            datetime.fromisoformat(item[key].replace("Z", "+00:00"))
        assert all(public_url(url) for url in item["imageUrls"])
    stats = json.loads((root / "public/stats.json").read_text(encoding="utf-8"))
    assert stats["total"] == len(ids)
    print(f"API valide : {len(ids)} annonces")


if __name__ == "__main__": validate()
