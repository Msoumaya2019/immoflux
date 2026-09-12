from . import leboncoin, seloger, bienici, pap, aci, authorized_json

REGISTRY = {p.ID: p for p in (leboncoin, seloger, bienici, pap, aci, authorized_json)}
