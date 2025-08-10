from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import json
import os
import subprocess
from cert_manager import generate_ssl

DOMAINS_FILE = "/etc/nginx/domains.json"

app = FastAPI(title="Dynamic Domain API", version="1.0")

class DomainRequest(BaseModel):
    domain: str
    target: str

@app.post("/api/add-domain")
def add_domain(req: DomainRequest):
    # Load existing domains
    if os.path.exists(DOMAINS_FILE):
        with open(DOMAINS_FILE, "r") as f:
            domains = json.load(f)
    else:
        domains = {}

    if req.domain in domains:
        raise HTTPException(status_code=400, detail="Domain already exists")

    # Save to file
    domains[req.domain] = req.target
    with open(DOMAINS_FILE, "w") as f:
        json.dump(domains, f, indent=2)

    # Generate SSL
    ssl_path = f"/etc/nginx/ssl/{req.domain}"
    os.makedirs(ssl_path, exist_ok=True)
    generate_ssl(req.domain, ssl_path)

    # Reload nginx
    subprocess.run(["nginx", "-s", "reload"])

    return {"status": "success", "domain": req.domain, "target": req.target}
