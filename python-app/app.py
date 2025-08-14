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
    """
    Terima dua format payload:
    1) Baru:   { "domain": "cc.isipage.my.id", "pool": "pool_public" }  # pool opsional
               -> kalau "pool" TIDAK dikirim, otomatis pakai "pool_public"
    2) Legacy: { "domain": "cc.isipage.my.id", "target": "103.250.11.31:2000" }
               -> dibuat pool khusus: pool__<domain> dengan satu backend
    """
    body = request.get_json(force=True) or {}
    domain = (body.get("domain") or "").strip().lower()
    pool   = (body.get("pool") or "").strip()          # bisa kosong → default ke pool_public
    target = (body.get("target") or "").strip()        # legacy

    if "." not in domain:
        return jsonify(ok=False, message="Invalid domain"), 400

    pools = load_json(POOLS_FILE, {})

    # 1) Jika format legacy "target" dipakai dan "pool" tidak diisi → buat pool khusus untuk domain
    if not pool and target:
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

    # 2) Jika tidak ada "pool" dan tidak ada "target" → default ke pool_public
    if not pool and not target:
        pool = "pool_public"

    # Pastikan pool yang direferensikan tersedia
    if pool not in pools:
        # Di sini kamu bisa pilih: (A) auto-gagal, atau (B) auto-buat pool_public bawaan.
        # Rekomendasi aman: gagal dengan pesan jelas.
        return jsonify(ok=False, message=f"Pool '{pool}' not found. Buat dulu via /api/add-pool atau pools.json"), 400

    # Baca domains.json (schema baru: list of {domain, pool})
    domains = load_json(DOMAINS_FILE, [])
    if isinstance(domains, dict):
        # Konversi schema lama (map domain->"host:port") ke schema baru
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

    # Upsert mapping domain → pool
    updated = False
    for item in domains:
        if item.get("domain") == domain:
            item["pool"] = pool
            updated = True
            break
    if not updated:
        domains.append({"domain": domain, "pool": pool})
    save_json(DOMAINS_FILE, domains)

    # Kickoff certbot non-blocking
    subprocess.Popen([
        "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
        "-d", domain, "--non-interactive", "--agree-tos", "-m", f"admin@{domain}",
        "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
        "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", domain
    ])

    # Reload nginx agar Lua re-load domains & pools
    reloaded = nginx_reload()
    msg = "Domain saved, certbot started, nginx reloaded" if reloaded else "Domain saved, certbot started (nginx reload failed)"
    return jsonify(ok=True, message=msg, domain=domain, pool=pool)


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
