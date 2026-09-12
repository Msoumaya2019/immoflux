import html
import json
import re
from html.parser import HTMLParser
from urllib.parse import urljoin
from .http import PoliteClient
from .result import PartialResult
from urllib.error import HTTPError
from .html import Document

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


def parse_cards(content, transaction="sale"):
    result = []
    for card in Document(content).root.find_all("search-list-item-alt"):
        title = card.find("item-title")
        price = card.find("item-price")
        location = title.find("h1") if title else None
        href = title.attrs.get("href", "") if title else ""
        match = re.fullmatch(r"/annonces/(maison|appartement|pavillon)-[^?]+-r(\d+)", href)
        city_match = re.fullmatch(r"\s*(.*?)\s*\((\d{5})\)\s*", location.text()) if location else None
        if not match or not city_match or not price:
            continue
        tags = card.find("item-tags")
        tags_text = tags.text() if tags else ""
        rooms = re.search(r"(\d+)\s*pièces?", tags_text)
        bedrooms = re.search(r"(\d+)\s*chambres?", tags_text)
        surface = re.search(r"([\d.,]+)\s*m²", tags_text)
        description = card.find("item-description")
        images = [x.attrs["src"] for x in card.tags("img") if x.attrs.get("src", "").startswith("https://cdn.pap.fr/")]
        result.append({"sourceListingId": match.group(2), "url": urljoin("https://www.pap.fr", href),
            "title": f"{match.group(1).capitalize()} à {city_match.group(1)}", "propertyType": match.group(1),
            "transactionType": transaction, "price": int(re.sub(r"\D", "", price.text())),
            "city": city_match.group(1), "postalCode": city_match.group(2),
            "rooms": int(rooms.group(1)) if rooms else None, "bedrooms": int(bedrooms.group(1)) if bedrooms else None,
            "surface": float(surface.group(1).replace(",", ".")) if surface else None,
            "description": ((description.text() if description else "") + "\n[Extrait de la liste PAP ; consulter la fiche originale pour le texte complet.]"),
            "imageUrls": images})
    return result


def fetch(config):
    if config.get("publicRedistributionAuthorized") is not True:
        raise ValueError("Public redistribution authorization required")
    pages = config.get("searchPages", [])
    if not pages or len(pages) > 5:
        raise ValueError("Configure 1 to 5 authorized PAP search pages")
    client = PoliteClient("https://www.pap.fr")
    links = {}
    cards = {}
    for entry in pages:
        content = client.get(entry["url"])
        page = Page(content)
        cards.update({x["url"]: x for x in parse_cards(content, entry.get("transactionType", "sale"))})
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
            if link in cards: result.append(cards[link])
            if error.code in (401, 403, 429):
                break  # Stop immediately on protection or throttling; never bypass/retry.
        except ValueError:
            warnings.append("fiche redirigée ou format modifié")
            if link in cards: result.append(cards[link])
    if warnings:
        if not result:
            raise ValueError("Aucune fiche récupérée : " + ", ".join(sorted(set(warnings))))
        return PartialResult(result, "Collecte partielle : " + ", ".join(sorted(set(warnings))) + ". Anciennes données conservées.")
    return result
