"""Import a licensed public JSON feed. No portal scraping or browser bypass."""
import ipaddress
import json
import socket
import time
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.robotparser import RobotFileParser

ID = "authorized_json"
NAME = "Flux JSON autorisé"
REASON = "Aucun flux autorisé configuré ; tests uniquement sur fixtures locales."
USER_AGENT = "ImmoFlux/1.0 (authorized-public-feed-reader)"
MAX_BYTES = 5_000_000


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Redirect refused: configure the final authorized HTTPS URL")


def safe_url(url):
    p = urlsplit(url)
    if p.scheme != "https" or not p.hostname or p.username or p.password or p.query or p.fragment or p.port not in (None, 443):
        raise ValueError("Expected a public HTTPS URL, without credentials, query or fragment")
    addresses = socket.getaddrinfo(p.hostname, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
        raise ValueError("Non-public destination refused")
    return url


def download(url):
    safe_url(url)
    with build_opener(NoRedirect).open(Request(url, headers={"User-Agent": USER_AGENT}), timeout=25) as response:
        data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("Feed exceeds 5 MB")
        return data.decode("utf-8-sig")


def decode_feed(text):
    payload = json.loads(text)
    if not isinstance(payload, dict) or not isinstance(payload.get("listings"), list):
        raise ValueError("Feed must contain a listings array")
    if len(payload["listings"]) > 5000 or not all(isinstance(x, dict) for x in payload["listings"]):
        raise ValueError("Invalid or oversized feed")
    return payload["listings"]


def fetch(config):
    if config.get("publicRedistributionAuthorized") is not True or not config.get("permissionReference"):
        raise ValueError("Explicit public redistribution authorization required")
    url = safe_url(config.get("url", ""))
    p = urlsplit(url)
    robots_url = f"https://{p.netloc}/robots.txt"
    # Fail closed for unavailable robots. Configure an explicitly permitted feed.
    robots = RobotFileParser()
    robots.parse(download(robots_url).splitlines())
    if not robots.can_fetch(USER_AGENT, url):
        raise ValueError("robots.txt disallows this feed")
    delay = max(3, robots.crawl_delay(USER_AGENT) or 0)
    if delay > 60:
        raise ValueError("Crawl-delay too long for this scheduled collector")
    rate = robots.request_rate(USER_AGENT)
    if rate and rate.requests > 0:
        delay = max(delay, rate.seconds / rate.requests)
    if delay > 60:
        raise ValueError("Request-rate exceeds collector time budget")
    time.sleep(delay)
    return decode_feed(download(url))
