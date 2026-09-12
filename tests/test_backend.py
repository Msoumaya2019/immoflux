import copy
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from backend.generate import generate, write_json
from backend.model import normalize, deduplicate, public_url, matches
from backend.providers.authorized_json import decode_feed, safe_url
from backend.providers.http import robots_allowed
from backend.providers.pap import Page, parse_detail

STAMP = "2026-09-12T08:00:00Z"


def raw(**overrides):
    return {"sourceListingId": "fixture-1", "title": "Maison de test", "url": "https://example.org/listing/1",
            "price": 350000, "surface": 100, "rooms": 5, "bedrooms": 3,
            "propertyType": "maison", "transactionType": "vente", "city": "Montmagny", "postalCode": "95360",
            "description": "Description de test. " * 10, "agency": "Agence de test", **overrides}


class ModelTests(unittest.TestCase):
    def test_normalization(self):
        item = normalize(raw(), "test", STAMP)
        self.assertEqual(item["pricePerSquareMeter"], 3500)
        self.assertEqual(item["propertyType"], "house")
        self.assertFalse(item["isFavorite"])

    def test_id_stable_when_price_changes(self):
        self.assertEqual(normalize(raw(), "a", STAMP)["id"], normalize(raw(price=1), "a", STAMP)["id"])

    def test_missing_fields_refused(self):
        for fields in ({"sourceListingId": ""}, {"url": "http://example.org"}, {"postalCode": "12"}, {"propertyType": "office"}):
            with self.assertRaises(ValueError): normalize(raw(**fields), "a", STAMP)

    def test_nonfinite_or_negative_numbers(self):
        item = normalize(raw(price=float("inf"), surface=-1, rooms=4.5), "a", STAMP)
        self.assertIsNone(item["price"]); self.assertIsNone(item["rooms"])
        self.assertIsNone(item["pricePerSquareMeter"])

    def test_coordinates_allow_negative_longitude(self):
        item = normalize(raw(latitude=48, longitude=-2), "a", STAMP)
        self.assertEqual(item["longitude"], -2)

    def test_urls_no_secrets(self):
        for url in ("https://user:pass@example.org/x", "https://example.org/x?token=x", "javascript:alert(1)"):
            self.assertIsNone(public_url(url))

    def test_filter_city_accent_and_rooms(self):
        item = normalize(raw(city="Évry"), "a", STAMP)
        self.assertTrue(matches(item, {"city": "evry", "minRooms": 4}))
        self.assertFalse(matches(item, {"city": "evry", "minRooms": 6}))

    def test_conservative_dedup(self):
        a = normalize(raw(description="Generic text"), "a", STAMP)
        b = normalize(raw(description="Generic text"), "b", STAMP)
        self.assertEqual(len(deduplicate([a, b])), 2)

    def test_merge_retains_source_identity(self):
        a = normalize(raw(), "a", STAMP); b = normalize(raw(), "b", STAMP)
        result = deduplicate([a, b])
        self.assertEqual(len(result), 1)
        self.assertEqual(len(result[0]["sources"]), 2)
        self.assertEqual(set(result[0]["memberIds"]), {a["id"], b["id"]})

    def test_different_city_never_merged(self):
        a = normalize(raw(), "a", STAMP); b = normalize(raw(city="Paris"), "b", STAMP)
        self.assertEqual(len(deduplicate([a, b])), 2)


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        write_json(self.root / "config/providers.json", {"good": {"enabled": True}, "bad": {"enabled": True}})
        write_json(self.root / "config/searches.json", {"searches": [{"city": "Montmagny", "minRooms": 0}], "retentionDays": 90})

    def tearDown(self): self.temp.cleanup()

    def providers(self, price=350000, bad=True):
        def fail(_): raise RuntimeError("private error details must not be published")
        return {"good": SimpleNamespace(NAME="Good", REASON="", fetch=lambda _: [raw(price=price)]),
                "bad": SimpleNamespace(NAME="Bad", REASON="", fetch=fail if bad else lambda _: [])}

    def test_provider_failure_isolated_and_redacted(self):
        items, states = generate(self.root, timestamp=STAMP, registry=self.providers())
        self.assertEqual(len(items), 1)
        self.assertEqual(states[1]["status"], "error")
        self.assertNotIn("private error", states[1]["message"])

    def test_price_history_survives_runs(self):
        generate(self.root, timestamp=STAMP, registry=self.providers())
        items, _ = generate(self.root, timestamp="2026-09-12T12:00:00Z", registry=self.providers(price=335000))
        item = items[0]
        self.assertEqual(item["firstSeenDate"], STAMP)
        self.assertEqual(item["previousPrice"], 350000)
        self.assertEqual(item["priceChange"], -15000)
        self.assertEqual(len(item["priceHistory"]), 2)
        items, _ = generate(self.root, timestamp="2026-09-12T16:00:00Z", registry=self.providers(price=335000))
        self.assertEqual(items[0]["previousPrice"], 350000)
        self.assertEqual(len(items[0]["priceHistory"]), 2)

    def test_failure_preserves_old_items_and_data_date(self):
        generate(self.root, timestamp=STAMP, registry=self.providers())
        failed = {"good": self.providers()["bad"]}
        items, _ = generate(self.root, timestamp="2026-09-13T08:00:00Z", registry=failed)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["lastSeenDate"], STAMP)
        data = json.loads((self.root / "public/listings.json").read_text())
        self.assertEqual(data["lastSuccessfulFetch"], STAMP)

    def test_disabled_provider_not_published(self):
        generate(self.root, timestamp=STAMP, registry=self.providers())
        write_json(self.root / "config/providers.json", {"good": {"enabled": False}})
        items, _ = generate(self.root, timestamp=STAMP, registry=self.providers())
        self.assertEqual(items, [])

    def test_retention_removes_old_items(self):
        generate(self.root, timestamp=STAMP, registry=self.providers())
        items, _ = generate(self.root, timestamp="2027-09-12T08:00:00Z", registry={"good": self.providers()["bad"]})
        self.assertEqual(items, [])

    def test_empty_install_not_healthy(self):
        generate(self.root, timestamp=STAMP, registry={})
        health = json.loads((self.root / "public/health.json").read_text())
        self.assertEqual(health["status"], "degraded")
        self.assertIsNone(health["lastSuccessfulFetch"])

    def test_invalid_batch_does_not_partially_write(self):
        provider = SimpleNamespace(NAME="Good", REASON="", fetch=lambda _: [raw(), raw(url="invalid")])
        items, states = generate(self.root, timestamp=STAMP, registry={"good": provider})
        self.assertEqual(items, []); self.assertEqual(states[0]["status"], "error")


class ProviderTests(unittest.TestCase):
    def test_json_feed_schema(self):
        self.assertEqual(len(decode_feed(json.dumps({"listings": [raw()]}))), 1)
        for text in ('[]', '{"listings": [1]}'):
            with self.assertRaises(ValueError): decode_feed(text)

    def test_private_network_rejected(self):
        with patch("socket.getaddrinfo", return_value=[(2, 1, 6, "", ("127.0.0.1", 443))]):
            with self.assertRaises(ValueError): safe_url("https://example.org/feed")

    def test_robots_wildcards_and_allow_precedence(self):
        rules = "User-agent: *\nDisallow: /*?*\nDisallow: /private/\nAllow: /private/public$\nCrawl-delay: 5\n"
        self.assertFalse(robots_allowed(rules, "https://example.org/x?secret=x")[0])
        self.assertTrue(robots_allowed(rules, "https://example.org/private/public")[0])
        self.assertFalse(robots_allowed(rules, "https://example.org/private/public/other")[0])
        self.assertEqual(robots_allowed(rules, "https://example.org/x")[1], 5)

    def test_pap_extracts_only_residential_links(self):
        page = Page('<a class="item-title" href="/annonces/maison-test-95360-r123">Test</a><a class="item-title" href="/annonces/bureau-test-r456">Bureau</a>')
        self.assertEqual(page.links, ["https://www.pap.fr/annonces/maison-test-95360-r123"])

    def test_pap_jsonld_not_contact_details(self):
        product = {"@type": "Product", "name": "Maison test", "description": "Jardin contact test@example.org 06 12 34 56 78",
                   "additionalProperty": [{"name": "Surface", "value": "100"}, {"name": "Type de bien", "value": "Maison"}],
                   "address": {"addressLocality": "Montmagny", "postalCode": "95360", "streetAddress": "Privée"},
                   "offers": {"price": 350000, "seller": {"name": "PERSONAL NAME"}}}
        item = parse_detail('<script type="application/ld+json">' + json.dumps(product) + '</script>', "https://www.pap.fr/annonces/maison-test-r123", "sale")
        self.assertNotIn("test@example", item["description"])
        self.assertNotIn("PERSONAL NAME", json.dumps(item))
        self.assertNotIn("Privée", json.dumps(item, ensure_ascii=False))


if __name__ == "__main__": unittest.main()
