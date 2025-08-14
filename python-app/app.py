from flask import Flask, request, jsonify
import json, os, subprocess

DOMAINS_FILE = "/etc/nginx/domains.json"  # schema baru: [ { "domain": "...", "pool": "..." }, ... ]
POOLS_FILE   = "/etc/nginx/pools.json"    # { "pool_name": [ { "host": "...", "port": 1234 }, ... ], ... }
CERTBOT_BASE = "/var/lib/certbot"

app = Flask(__name__)

def load_json(path, default):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
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

@app.get("/api/domains")
def list_domains():
    return jsonify(ok=True, data=load_json(DOMAINS_FILE, []))

@app.get("/api/pools")
def list_pools():
    return jsonify(ok=True, data=load_json(POOLS_FILE, {}))

@app.post("/api/add-pool")
def add_pool():
    body = request.get_json(force=True) or {}
    name = (body.get("name") or "").strip()
    backends = body.get("backends") or []
    if not name or not isinstance(backends, list) or not backends:
        return jsonify(ok=False, message="Invalid payload: require name & non-empty backends[]"), 400

    norm = []
    for b in backends:
        host = (b.get("host") or "").strip()
        if not host:
            return jsonify(ok=False, message="backend.host required"), 400
        try:
            port = int(b.get("port") or 80)
        except Exception:
            return jsonify(ok=False, message="backend.port must be int"), 400
        norm.append({"host": host, "port": port})

    pools = load_json(POOLS_FILE, {})
    pools[name] = norm
    save_json(POOLS_FILE, pools)

    reloaded = nginx_reload()
    return jsonify(ok=True, message="Pool saved & nginx reloaded" if reloaded else "Pool saved (nginx reload failed)")


@app.post("/api/add-domain")
def add_domain():
    """
    Terima dua format payload:
    1) Baru: { "domain": "cc.isipage.my.id", "pool": "pool_public" }
    2) Legacy: { "domain": "cc.isipage.my.id", "target": "103.250.11.31:2000" }
       -> akan dibuatkan pool khusus: pool__<domain> dengan satu backend
    """
    body = request.get_json(force=True) or {}
    domain = (body.get("domain") or "").strip().lower()
    pool   = (body.get("pool") or "").strip()
    target = (body.get("target") or "").strip()  # legacy

    if "." not in domain:
        return jsonify(ok=False, message="Invalid domain"), 400

    # Siapkan pools.json
    pools = load_json(POOLS_FILE, {})

    # Jika masih pakai "target", buat pool khusus untuk domain ini
    if not pool and target:
        # target bisa "host:port" atau "host" saja
        host = target
        port = 80
        if ":" in target:
            host, p = target.rsplit(":", 1)
            host = host.strip()
            try:
                port = int(p)
            except Exception:
                return jsonify(ok=False, message="Invalid target port"), 400
        pool = f"pool__{domain}"
        pools[pool] = [{"host": host, "port": port}]
        save_json(POOLS_FILE, pools)

    if not pool:
        return jsonify(ok=False, message="Missing 'pool' (or legacy 'target')"), 400

    # Pastikan pool yang diminta ada (kecuali barusan dibuat dari 'target')
    if pool not in pools:
        return jsonify(ok=False, message=f"Pool '{pool}' not found"), 400

    # Baca domains.json (schema baru = list of {domain, pool})
    domains = load_json(DOMAINS_FILE, [])
    # Jika domains.json lama berbentuk dict, konversi
    if isinstance(domains, dict):
        # Konversi map {domain: "host:port"} ke schema baru, pakai pool satuan per domain
        converted = []
        for k, v in domains.items():
            legacy_pool = f"pool__{k}"
            h, pr = (v, 80)
            if ":" in v:
                h, pr_s = v.rsplit(":", 1)
                try:
                    pr = int(pr_s)
                except Exception:
                    pr = 80
            pools.setdefault(legacy_pool, [{"host": h, "port": pr}])
            converted.append({"domain": k, "pool": legacy_pool})
        domains = converted
        save_json(POOLS_FILE, pools)

    # Update/insert
    found = False
    for item in domains:
        if item.get("domain") == domain:
            item["pool"] = pool
            found = True
            break
    if not found:
        domains.append({"domain": domain, "pool": pool})

    save_json(DOMAINS_FILE, domains)

    # Jalankan certbot di background (biar non-blocking)
    subprocess.Popen([
        "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
        "-d", domain, "--non-interactive", "--agree-tos", "-m", f"admin@{domain}",
        "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
        "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", domain
    ])

    reloaded = nginx_reload()
    msg = "Domain saved, certbot started, nginx reloaded" if reloaded else "Domain saved, certbot started (nginx reload failed)"
    return jsonify(ok=True, message=msg, domain=domain, pool=pool)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
