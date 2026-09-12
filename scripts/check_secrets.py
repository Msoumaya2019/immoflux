"""Fast local guard; full-history Gitleaks runs in CI. Never prints matching values."""
import re
from pathlib import Path

patterns = [r"gh[pousr]_" + r"[A-Za-z0-9]{30,}", r"github_pat_" + r"[A-Za-z0-9_]{40,}",
            r"-----BEGIN " + r"(?:RSA |EC |OPENSSH )?PRIVATE KEY-----", r"AKIA" + r"[A-Z0-9]{16}"]
for path in Path(".").rglob("*"):
    if not path.is_file() or any(p in {".git", ".build", "build", "__pycache__", ".tools", "work"} for p in path.parts): continue
    if path.suffix in {".pem", ".p12", ".mobileprovision", ".key", ".pfx"}:
        raise SystemExit(f"Forbidden secret file: {path}")
    if path.stat().st_size > 20_000_000: continue
    try: text = path.read_text(encoding="utf-8")
    except UnicodeError: continue
    if any(re.search(pattern, text) for pattern in patterns):
        raise SystemExit(f"Potential secret in {path}; value redacted")
print("Local secret guard passed")
