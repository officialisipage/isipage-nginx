from flask import Flask, request, jsonify
import json, os, subprocess
import socket
def has_dns(host):
    try:
        socket.getaddrinfo(host, 80)
        return True
    except Exception:
        return False

DOMAINS_FILE = "/etc/nginx/domains.json"  # schema baru: [ { "domain": "...", "pool": "..." }, ... ]
POOLS_FILE   = "/etc/nginx/pools.json"    # { "pool_name": [ { "host": "...", "port": 1234 }, ... ], ... }
CERTBOT_BASE = "/var/lib/certbot"

app = Flask(__name__)

# === Security: API Key ===
SECRET_TOKEN = os.environ.get("SECRET_TOKEN", "m1xkekt2epaomzl9s08t")

@app.before_request
def check_auth():
    if request.path.startswith("/api/"):
        token = request.headers.get("X-API-KEY")
        if token != SECRET_TOKEN:
            return jsonify(ok=False, message="Forbidden"), 403
            
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

@app.post("/api/reload-nginx")
def reload_nginx():
    """
    Trigger reload nginx secara manual
    """
    reloaded = nginx_reload()
    if reloaded:
        return jsonify(ok=True, message="Nginx reload success")
    else:
        return jsonify(ok=False, message="Nginx reload failed"), 500

@app.post("/api/add-pool")
def add_pool():
    """Tambah/ubah pool backend ke pools.json"""
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
    return jsonify(
        ok=True,
        message="Pool saved & nginx reloaded" if reloaded else "Pool saved (nginx reload failed)",
        pool=name,
        backends=norm
    )


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

    # Update/insert untuk domain utama
    found = False
    for item in domains:
        if item.get("domain") == domain:
            item["pool"] = pool
            found = True
            break
    if not found:
        domains.append({"domain": domain, "pool": pool})

    # Tambahkan juga untuk www.domain
    www_domain = f"www.{domain}"
    found_www = False
    for item in domains:
        if item.get("domain") == www_domain:
            item["pool"] = pool
            found_www = True
            break
    if not found_www:
        domains.append({"domain": www_domain, "pool": pool})

    save_json(DOMAINS_FILE, domains)

    # Jalankan certbot di background (biar non-blocking)
    to_issue = [domain]
    www_domain = f"www.{domain}"
    if has_dns(www_domain):
        to_issue.append(www_domain)

    args = [
        "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
        "--non-interactive", "--agree-tos", "-m", f"admin@{domain}",
        "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
        "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", domain
    ]
    for d in to_issue:
        args.extend(["-d", d])

    subprocess.Popen(args)


    reloaded = nginx_reload()
    msg = "Domain saved, certbot started, nginx reloaded" if reloaded else "Domain saved, certbot started (nginx reload failed)"
    return jsonify(ok=True, message=msg, domain=domain, pool=pool)

# === util kecil: pastikan domains.json pakai schema baru (list of {domain,pool}) ===
def _ensure_domains_schema(domains, pools):
    if isinstance(domains, dict):
        # konversi map legacy { "a.domain": "host:port" } -> schema baru
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
        save_json(POOLS_FILE, pools)
        return converted
    return domains

@app.put("/api/update-domain")
def update_domain():
    """
    Update/rename domain:
    Body:
      {
        "old_domain": "aaa.isipage.my.id",
        "new_domain": "uuu.isipage.my.id",  # boleh sama dengan old untuk hanya ganti pool
        "pool": "pool_public"               # optional; kalau kosong/tidak ada -> pool tidak diubah
      }
    - Validasi: pool yang diberikan harus ada di pools.json
    - Jika rename (old != new): certbot dijalankan untuk new_domain (non-blocking)
    """
    body = request.get_json(force=True) or {}

    old_domain = (body.get("old_domain") or "").strip().lower()
    new_domain = (body.get("new_domain") or "").strip().lower()
    new_pool   = (body.get("pool") or "").strip()

    if "." not in old_domain:
        return jsonify(ok=False, message="Invalid old_domain"), 400
    if not new_domain:
        new_domain = old_domain
    if "." not in new_domain:
        return jsonify(ok=False, message="Invalid new_domain"), 400

    pools = load_json(POOLS_FILE, {})
    domains = load_json(DOMAINS_FILE, [])
    domains = _ensure_domains_schema(domains, pools)

    # Cari entry lama
    idx = None
    for i, item in enumerate(domains):
        if (item.get("domain") or "").lower() == old_domain:
            idx = i
            break
    if idx is None:
        return jsonify(ok=False, message=f"Domain '{old_domain}' not found"), 404

    # Update pool jika diberikan dan tidak kosong
    if new_pool:
        if new_pool not in pools:
            return jsonify(ok=False, message=f"Pool '{new_pool}' not found"), 400
        domains[idx]["pool"] = new_pool

    # Rename domain jika berubah
    renamed = False
    if new_domain != old_domain:
        # Cek apakah new_domain sudah ada; jika ada, kita overwrite (hapus yang lama)
        existing_idx = None
        for i, item in enumerate(domains):
            if (item.get("domain") or "").lower() == new_domain:
                existing_idx = i
                break
        if existing_idx is not None and existing_idx != idx:
            # gabungkan: gunakan pool dari hasil update (domains[idx])
            domains[existing_idx]["pool"] = domains[idx]["pool"]
            # hapus yang old
            domains.pop(idx)
        else:
            domains[idx]["domain"] = new_domain
        renamed = True

    save_json(DOMAINS_FILE, domains)

    # Jika rename -> jalankan certbot untuk domain baru (non-blocking)
    if renamed:
        to_issue = [new_domain]
        www_new = f"www.{new_domain}"
        if has_dns(www_new):
            to_issue.append(www_new)

        args = [
            "/usr/bin/certbot", "certonly", "--webroot", "-w", "/var/www/certbot",
            "--non-interactive", "--agree-tos", "-m", f"admin@{new_domain}",
            "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
            "--logs-dir", f"{CERTBOT_BASE}/logs", "--cert-name", new_domain
        ]
        for d in to_issue:
            args.extend(["-d", d])

        subprocess.Popen(args)


    reloaded = nginx_reload()
    return jsonify(
        ok=True,
        message=("Updated & nginx reloaded" if reloaded else "Updated (nginx reload failed)"),
        old_domain=old_domain,
        new_domain=new_domain,
        pool=(new_pool or "unchanged")
    )


@app.delete("/api/delete-domain")
def delete_domain():
    """
    Hapus mapping domain dari domains.json.
    Body:
      {
        "domain": "aaa.isipage.my.id",
        "remove_cert": false   # optional; jika true maka coba hapus sertifikat LE
      }
    Catatan:
    - pools.json tidak disentuh (pool tetap ada).
    - Jika remove_cert=true -> jalankan `certbot delete --cert-name <domain>` (non-blocking).
    """
    body = request.get_json(force=True) or {}
    domain = (body.get("domain") or "").strip().lower()
    remove_cert = bool(body.get("remove_cert", False))

    if "." not in domain:
        return jsonify(ok=False, message="Invalid domain"), 400

    pools = load_json(POOLS_FILE, {})
    domains = load_json(DOMAINS_FILE, [])
    domains = _ensure_domains_schema(domains, pools)

    before = len(domains)
    domains = [d for d in domains if (d.get("domain") or "").lower() != domain]
    if len(domains) == before:
        return jsonify(ok=False, message=f"Domain '{domain}' not found"), 404

    save_json(DOMAINS_FILE, domains)

    # Optional: hapus cert
    if remove_cert:
        # Jalankan non-blocking; certbot akan menghapus entry & symlink; direktori bisa tertinggal jika custom config-dir
        subprocess.Popen([
            "/usr/bin/certbot", "delete",
            "--cert-name", domain,
            "--config-dir", CERTBOT_BASE, "--work-dir", f"{CERTBOT_BASE}/work",
            "--logs-dir", f"{CERTBOT_BASE}/logs", "-n",  # non-interactive
        ])

    reloaded = nginx_reload()
    return jsonify(
        ok=True,
        message=("Deleted & nginx reloaded" if reloaded else "Deleted (nginx reload failed)"),
        domain=domain,
        remove_cert=remove_cert
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
