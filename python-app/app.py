from flask import Flask, request, jsonify
import json, os, subprocess, time

DOMAINS_FILE = "/etc/nginx/domains.json"
CERTBOT_BASE = "/var/lib/certbot"

app = Flask(__name__)

@app.route("/api/add-domain", methods=["POST"])
def add_domain():
    data = request.get_json(force=True)
    domain = data.get("domain", "").strip()
    target = data.get("target", "103.250.11.31:2000")

    if "." not in domain:
        return jsonify(ok=False, message="Invalid domain"), 400

    # Update domains.json
    try:
        with open(DOMAINS_FILE, "r") as f:
            domains = json.load(f)
    except:
        domains = {}
    domains[domain] = target
    with open(DOMAINS_FILE, "w") as f:
        json.dump(domains, f)

    # Jalankan certbot di background
    subprocess.Popen([
        "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
        "-d", domain, "--non-interactive", "--agree-tos", "-m", f"admin@{domain}",
        "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
        "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", domain
    ])

    return jsonify(ok=True, message="Saved & certbot started", domain=domain, target=target)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
