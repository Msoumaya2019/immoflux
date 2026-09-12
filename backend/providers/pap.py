import html
import json
import re
from html.parser import HTMLParser
from urllib.parse import urljoin
from .http import PoliteClient
from .result import PartialResult
from urllib.error import HTTPError

ID = "pap"
NAME = "PAP"
REASON = "Collecte limitée aux premières pages autorisées ; aucune pagination /proximite/."


class Page(HTMLParser):
    def __init__(self, content):
        super().__init__(convert_charrefs=True)
        self.links = []
        self.json_blocks = []
        self.in_json = False
        self.block = ""
        self.text = []
        self.feed(content)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "item-title" in attrs.get("class", "").split():
            href = attrs.get("href", "")
            if re.fullmatch(r"/annonces/(?:maison|appartement|pavillon)-[^?]+-r\d+", href):
                self.links.append(urljoin("https://www.pap.fr", href))
        if tag == "script" and attrs.get("type") == "application/ld+json":
            self.in_json = True; self.block = ""

    def handle_data(self, data):
        if self.in_json: self.block += data
        else: self.text.append(data)

    def handle_endtag(self, tag):
        if tag == "script" and self.in_json:
            self.json_blocks.append(json.loads(self.block)); self.in_json = False


def parse_detail(content, url, transaction):
    page = Page(content)
    product = next((x for x in page.json_blocks if isinstance(x, dict) and x.get("@type") == "Product"), None)
    if not product:
        raise ValueError("PAP Product JSON-LD missing; page changed or listing withdrawn")
    props = {p["name"]: p.get("value") for p in product.get("additionalProperty", [])}
    address = product.get("address", {})
    match = re.search(r"-r(\d+)$", url)
    bedrooms = re.search(r"(\d+)\s+chambres?", " ".join(page.text))
    images = product.get("image", [])
    description = html.unescape(product.get("description", ""))
    # Do not export seller names, contact details or exact street addresses.
    description = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[coordonnées retirées]", description)
    description = re.sub(r"(?<!\d)(?:\+33\s?|0)[1-9](?:[ .-]?\d{2}){4}(?!\d)", "[téléphone retiré]", description)
    return {"sourceListingId": match.group(1), "url": url, "title": html.unescape(product["name"]),
            "price": product.get("offers", {}).get("price"), "surface": props.get("Surface"),
            "rooms": props.get("Nombre de pièces"), "bedrooms": int(bedrooms.group(1)) if bedrooms else None,
            "propertyType": str(props.get("Type de bien", "")).lower(), "transactionType": transaction,
            "city": address.get("addressLocality"), "postalCode": address.get("postalCode"),
            "description": description, "imageUrls": images if isinstance(images, list) else [images],
            "agency": "", "landSurface": props.get("Surface du terrain")}


def fetch(config):
    if config.get("publicRedistributionAuthorized") is not True:
        raise ValueError("Public redistribution authorization required")
    pages = config.get("searchPages", [])
    if not pages or len(pages) > 5:
        raise ValueError("Configure 1 to 5 authorized PAP search pages")
    client = PoliteClient("https://www.pap.fr")
    links = {}
    for entry in pages:
        page = Page(client.get(entry["url"]))
        if not page.links:
            raise ValueError("No PAP listing links; parser must be verified")
        for link in page.links[:20]:
            links[link] = entry.get("transactionType", "sale")
    result = []
    warnings = []
    for link, transaction in list(links.items())[:30]:
        try:
            result.append(parse_detail(client.get(link), link, transaction))
        except HTTPError as error:
            warnings.append(f"HTTP {error.code}")
            if error.code in (401, 403, 429):
                break  # Stop immediately on protection or throttling; never bypass/retry.
        except ValueError:
            warnings.append("fiche redirigée ou format modifié")
    if warnings:
        if not result:
            raise ValueError("Aucune fiche récupérée : " + ", ".join(sorted(set(warnings))))
        return PartialResult(result, "Collecte partielle : " + ", ".join(sorted(set(warnings))) + ". Anciennes données conservées.")
    return result
