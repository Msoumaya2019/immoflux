import re
import time
from urllib.parse import urlsplit
from .authorized_json import download, USER_AGENT


def robots_allowed(text, url, agent=USER_AGENT):
    groups = []
    agents, rules = [], []
    for line in text.splitlines() + ["User-agent: __end__"]:
        line = line.split("#", 1)[0].strip()
        if ":" not in line:
            continue
        key, value = (x.strip() for x in line.split(":", 1))
        key = key.lower()
        if key == "user-agent":
            if rules:
                groups.append((agents, rules)); agents, rules = [], []
            agents.append(value.lower())
        elif agents and key in ("allow", "disallow", "crawl-delay"):
            rules.append((key, value))
    exact = [(a, r) for a, r in groups if any(x != "*" and x in agent.lower() for x in a)]
    selected = exact or [(a, r) for a, r in groups if "*" in a]
    path = urlsplit(url).path + ("?" + urlsplit(url).query if urlsplit(url).query else "")
    matches = []
    delay = 3.0
    for _, rules in selected:
        for key, value in rules:
            if key == "crawl-delay":
                try: delay = max(delay, float(value))
                except ValueError: pass
            elif value:
                pattern = re.escape(value).replace(r"\*", ".*")
                if pattern.endswith(r"\$"):
                    pattern = pattern[:-2] + "$"
                if re.match(pattern, path):
                    matches.append((len(value.replace("*", "")), key == "allow"))
    return (max(matches)[1] if matches else True), delay


class PoliteClient:
    def __init__(self, origin):
        self.origin = origin
        self.robots = download(origin + "/robots.txt")
        self.last_request = time.monotonic()

    def get(self, url):
        if f"https://{urlsplit(url).netloc}" != self.origin:
            raise ValueError("Cross-origin fetch refused")
        allowed, delay = robots_allowed(self.robots, url)
        if not allowed or delay > 60:
            raise ValueError("robots.txt restriction")
        time.sleep(max(0, delay - (time.monotonic() - self.last_request)))
        try:
            return download(url)
        finally:
            self.last_request = time.monotonic()
