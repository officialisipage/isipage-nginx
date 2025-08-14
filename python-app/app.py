from flask import Flask, request, jsonify
import json, os, subprocess

DOMAINS_FILE = "/etc/nginx/domains.json"
POOLS_FILE   = "/etc/nginx/pools.json"
CERTBOT_BASE = "/var/lib/certbot"

app = Flask(__name__)

def load_json(path, default):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def nginx_reload():
    try:
        subprocess.run(["nginx", "-t"], check=True)
        subprocess.run(["nginx", "-s", "reload"], check=True)
        return True
    except Exception as e:
        app.logger.error(f"Nginx reload failed: {e}")
        return False

@app.route("/api/domains", methods=["GET"])
def list_domains():
    data = load_json(DOMAINS_FILE, [])
    return jsonify(ok=True, data=data)

@app.route("/api/pools", methods=["GET"])
def list_pools():
    data = load_json(POOLS_FILE, {})
    return jsonify(ok=True, data=data)

@app.route("/api/add-domain", methods=["POST"])
def add_domain():
    data = request.get_json(force=True)
    domain = data.get("domain", "").strip()
    target = data.get("target", "").strip()

    if "." not in domain:
        return jsonify(ok=False, message="Invalid domain"), 400

    # jika tidak ada target di payload, pakai default pool_public
    if not target:
        target = "pool_public"

    # Update domains.json
    try:
        with open(DOMAINS_FILE, "r") as f:
            domains = json.load(f)
    except:
        domains = {}
    domains[domain] = target
    with open(DOMAINS_FILE, "w") as f:
        json.dump(domains, f, indent=2)

    # Jalankan certbot di background
    subprocess.Popen([
        "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
        "-d", domain, "--non-interactive", "--agree-tos", "-m", f"admin@{domain}",
        "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
        "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", domain
    ])

    return jsonify(ok=True, message="Saved & certbot started", domain=domain, target=target)

@app.route("/api/add-pool", methods=["POST"])
def add_pool():
    body = request.get_json(force=True)
    name = (body.get("name") or "").strip()
    backends = body.get("backends") or []

    if not name or not isinstance(backends, list) or len(backends) == 0:
        return jsonify(ok=False, message="Invalid payload: require name & non-empty backends[]"), 400

    # normalize backends (host, port)
    norm = []
    for b in backends:
        host = (b.get("host") or "").strip()
        port = int(b.get("port") or 80)
        if not host:
            return jsonify(ok=False, message="backend.host required"), 400
        norm.append({"host": host, "port": port})

    pools = load_json(POOLS_FILE, {})
    pools[name] = norm
    save_json(POOLS_FILE, pools)

    reloaded = nginx_reload()
    return jsonify(ok=True, message="Pool saved & nginx reloaded" if reloaded else "Pool saved (nginx reload failed)")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
