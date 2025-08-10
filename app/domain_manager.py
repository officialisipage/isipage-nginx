import json
import os

DOMAINS_FILE = "/etc/nginx/domains.json"

def load_domains():
    if os.path.exists(DOMAINS_FILE):
        with open(DOMAINS_FILE, "r") as f:
            return json.load(f)
    return {}

def save_domain(domain: str, target: str):
    domains = load_domains()
    domains[domain] = target
    with open(DOMAINS_FILE, "w") as f:
        json.dump(domains, f, indent=2)
