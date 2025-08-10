# app.py
import os
import json
import subprocess
from flask import Flask, request, jsonify, abort
from utils import read_domains, write_domains, generate_domains_map, ensure_dir, copy_cert_from_letsencrypt

DOMAINS_JSON = "/etc/nginx/domains.json"
DOMAINS_MAP = "/etc/nginx/conf.d/domains.map"
WEBROOT = "/var/www/certbot"
LETSENCRYPT_LIVE = "/etc/letsencrypt/live"
NGINX_SSL_BASE = "/etc/nginx/ssl"
API_KEY = os.environ.get("API_KEY", "")

app = Flask(__name__)

def require_api_key():
    key = request.headers.get("X-API-KEY") or request.args.get("api_key")
    if not key or key != API_KEY:
        abort(401)

@app.route("/api/list-domains", methods=["GET"])
def list_domains():
    require_api_key()
    domains = read_domains(DOMAINS_JSON)
    result = {}
    for d, t in domains.items():
        cert_exists = os.path.exists(os.path.join(NGINX_SSL_BASE, d, "fullchain.pem")) and \
                      os.path.exists(os.path.join(NGINX_SSL_BASE, d, "privkey.pem"))
        result[d] = {"target": t, "has_cert": cert_exists}
    return jsonify(result)

@app.route("/api/add-domain", methods=["POST", "GET"])
def add_domain():
    # support JSON body or query params
    require_api_key()
    data = request.get_json(silent=True) or {}
    domain = data.get("domain") or request.args.get("domain")
    target = data.get("target") or request.args.get("target")
    email  = data.get("email") or request.args.get("email") or "admin@" + (domain or "example.com")

    if not domain or not target:
        return jsonify({"error": "missing domain or target"}), 400

    # update domains.json + map
    domains = read_domains(DOMAINS_JSON)
    domains[domain] = target
    write_domains(DOMAINS_JSON, domains)
    generate_domains_map(domains, DOMAINS_MAP)
    subprocess.run(["nginx", "-s", "reload"], check=False)

    # ensure webroot
    ensure_dir(WEBROOT)

    # run certbot certonly with deploy-hook that copies files to /etc/nginx/ssl/{domain}
    # deploy-hook will be executed after certificate is obtained/renewed
    deploy_cmd = (
        "cp /etc/letsencrypt/live/{d}/fullchain.pem /etc/nginx/ssl/{d}/fullchain.pem && "
        "cp /etc/letsencrypt/live/{d}/privkey.pem /etc/nginx/ssl/{d}/privkey.pem"
    ).format(d=domain)

    cmd = [
        "certbot", "certonly", "--webroot", "-w", WEBROOT,
        "-d", domain,
        "--email", email,
        "--agree-tos",
        "--non-interactive",
        "--expand",
        "--deploy-hook", deploy_cmd,
        "--no-eff-email"
    ]

    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = p.stdout

    # after certbot, try copy (in case deploy-hook didn't run)
    ok, msg = copy_cert_from_letsencrypt(domain, LETSENCRYPT_LIVE, NGINX_SSL_BASE)
    if ok:
        subprocess.run(["nginx", "-s", "reload"], check=False)
        return jsonify({"ok": True, "certbot": out, "copy": msg})
    else:
        return jsonify({"ok": False, "certbot": out, "copy_error": msg}), 500

@app.route("/api/check/<domain>", methods=["GET"])
def check(domain):
    require_api_key()
    cert_path = os.path.join(NGINX_SSL_BASE, domain, "fullchain.pem")
    key_path = os.path.join(NGINX_SSL_BASE, domain, "privkey.pem")
    ok = os.path.exists(cert_path) and os.path.exists(key_path)
    return jsonify({"domain": domain, "has_cert": ok})

@app.route("/api/renew", methods=["POST"])
def renew():
    require_api_key()
    # renew all certs that need it; use webroot, and use deploy-hook to copy back
    deploy_cmd = "for d in $(ls /etc/letsencrypt/live); do cp /etc/letsencrypt/live/$d/fullchain.pem /etc/nginx/ssl/$d/fullchain.pem 2>/dev/null || true; cp /etc/letsencrypt/live/$d/privkey.pem /etc/nginx/ssl/$d/privkey.pem 2>/dev/null || true; done"
    cmd = ["certbot", "renew", "--webroot", "-w", WEBROOT, "--deploy-hook", deploy_cmd, "--quiet"]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = p.stdout
    # copy for all domains in domains.json to be safe
    domains = read_domains(DOMAINS_JSON)
    copy_results = {}
    for d in domains.keys():
        ok, msg = copy_cert_from_letsencrypt(d, LETSENCRYPT_LIVE, NGINX_SSL_BASE)
        copy_results[d] = {"copied": ok, "msg": msg}
    subprocess.run(["nginx", "-s", "reload"], check=False)
    return jsonify({"ok": True, "certbot_output": out, "copies": copy_results})

if __name__ == "__main__":
    # init
    os.makedirs("/etc/nginx/conf.d", exist_ok=True)
    os.makedirs(WEBROOT, exist_ok=True)
    os.makedirs(NGINX_SSL_BASE, exist_ok=True)
    if not os.path.exists(DOMAINS_JSON):
        with open(DOMAINS_JSON, "w") as f:
            json.dump({}, f)
    generate_domains_map(read_domains(DOMAINS_JSON), DOMAINS_MAP)
    app.run(host="0.0.0.0", port=5000)
