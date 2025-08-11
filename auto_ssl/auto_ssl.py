
#!/usr/bin/env python3
"""
Auto-SSL manager for Nginx/OpenResty using Certbot (webroot).
- Adds/updates domain target in /etc/nginx/domains.json (atomic write)
- Issues certificate via certbot using webroot challenge
- Fixes permissions so Nginx can read cert/key
- Reloads Nginx on success
- Provides a tiny FastAPI service for POST /api/add-domain
Environment defaults are overridable via env vars.
"""

import os
import json
import subprocess
import tempfile
import shutil
import sys
from pathlib import Path
from typing import Optional

# ---- Config (overridable via env) ----
DOMAINS_JSON = Path(os.getenv("DOMAINS_JSON", "/etc/nginx/domains.json"))
WEBROOT_DIR  = Path(os.getenv("WEBROOT_DIR", "/var/www/certbot"))
CERT_DIR     = Path(os.getenv("CERT_DIR", "/var/lib/certbot"))
NGINX_CMD    = os.getenv("NGINX_CMD", "nginx -s reload")
NGINX_USER   = os.getenv("NGINX_USER", "nginx")  # set to 'root' if your workers run as root
ADMIN_EMAIL  = os.getenv("ADMIN_EMAIL", None)    # if None -> admin@{domain}
RSA_KEY_SIZE = os.getenv("RSA_KEY_SIZE", "4096")

# ---- Helpers ----
def _ensure_dirs():
    WEBROOT_DIR.mkdir(parents=True, exist_ok=True)
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    # Make webroot world-readable (Let’s Encrypt CA bot must reach the file via Nginx, not file perms, but safe defaults)
    WEBROOT_DIR.chmod(0o755)

def _atomic_write_json(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', delete=False, dir=str(path.parent)) as tf:
        json.dump(data, tf, indent=2, sort_keys=True)
        tmp_name = tf.name
    os.replace(tmp_name, path)

def _load_domains() -> dict:
    if not DOMAINS_JSON.exists():
        return {}
    try:
        with DOMAINS_JSON.open() as f:
            return json.load(f)
    except Exception:
        return {}

def _set_domains_permissions():
    # Let nginx worker read/update JSON (optional, depends on how you call it)
    try:
        gid = grp.getgrnam(NGINX_USER).gr_gid
    except KeyError:
        # If user is not a group, try user
        try:
            gid = pwd.getpwnam(NGINX_USER).pw_gid
        except KeyError:
            return
    try:
        os.chown(DOMAINS_JSON, 0, gid)
        os.chmod(DOMAINS_JSON, 0o664)
    except PermissionError:
        pass

def _fix_cert_permissions(domain: str):
    """Give nginx read access to cert/key. Certbot sets strict perms (600)."""
    live = CERT_DIR / "live" / domain
    full = live / "fullchain.pem"
    key  = live / "privkey.pem"
    if not full.exists() or not key.exists():
        return
    # chgrp nginx and 640 on privkey, 644 on fullchain
    try:
        gid = grp.getgrnam(NGINX_USER).gr_gid
    except KeyError:
        try:
            gid = pwd.getpwnam(NGINX_USER).pw_gid
        except KeyError:
            gid = -1
    try:
        if gid != -1:
            os.chown(key, 0, gid)
            os.chown(full, 0, gid)
        os.chmod(key, 0o640)
        os.chmod(full, 0o644)
    except PermissionError:
        # If running non-root container, you may need to relax certbot umask or run with proper permissions
        pass

def _run(cmd: list[str]) -> tuple[int, str]:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out, _ = p.communicate()
    return p.returncode, out

def add_or_update_domain(domain: str, target: Optional[str]) -> dict:
    if not domain or "." not in domain:
        return {"ok": False, "message": "Invalid domain"}

    _ensure_dirs()

    # Update domains.json atomically
    domains = _load_domains()
    if target:
        domains[domain] = target
    elif domain not in domains:
        # keep existing if only issuing cert
        domains[domain] = "127.0.0.1:2000"
    _atomic_write_json(DOMAINS_JSON, domains)
    _set_domains_permissions()

    # Touch a test file so user can curl quickly
    (WEBROOT_DIR / ".well-known" / "acme-challenge").mkdir(parents=True, exist_ok=True)
    testfile = WEBROOT_DIR / ".well-known" / "acme-challenge" / "self-check.txt"
    testfile.write_text("acme-ok")

    email = ADMIN_EMAIL or f"admin@{domain}"
    cmd = [
        "certbot", "certonly",
        "--webroot", "-w", str(WEBROOT_DIR),
        "-d", domain,
        "--non-interactive", "--agree-tos",
        "-m", email,
        "--expand",
        "--logs-dir", "/tmp",
        "--work-dir", "/tmp",
        "--config-dir", str(CERT_DIR),
        "--rsa-key-size", RSA_KEY_SIZE,
        # Avoid permission checks that fail in containers with custom layout
        "--no-permissions-check",
    ]
    code, out = _run(cmd)

    result = {"ok": code == 0, "code": code, "output": out}

    # Fix perms and reload
    if code == 0:
        _fix_cert_permissions(domain)
        _run(NGINX_CMD.split(" "))
        result["reloaded"] = True
    else:
        result["reloaded"] = False

    return result

# ---- CLI mode ----
def _cli():
    import argparse
    p = argparse.ArgumentParser(description="Auto-SSL manager")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_add = sub.add_parser("add-domain", help="Add/update domain and issue cert")
    p_add.add_argument("--domain", required=True)
    p_add.add_argument("--target", required=False)

    p_issue = sub.add_parser("issue", help="Issue/renew cert for existing domain")
    p_issue.add_argument("--domain", required=True)

    p_renew = sub.add_parser("renew-all", help="Run certbot renew and reload nginx if changed")

    args = p.parse_args()
    if args.cmd == "add-domain":
        r = add_or_update_domain(args.domain, args.target)
        print(json.dumps(r, indent=2))
        sys.exit(0 if r["ok"] else 1)
    elif args.cmd == "issue":
        r = add_or_update_domain(args.domain, None)
        print(json.dumps(r, indent=2))
        sys.exit(0 if r["ok"] else 1)
    elif args.cmd == "renew-all":
        cmd = [
            "certbot", "renew",
            "--logs-dir", "/tmp",
            "--work-dir", "/tmp",
            "--config-dir", str(CERT_DIR),
            "--no-permissions-check",
            "--deploy-hook", NGINX_CMD,
        ]
        code, out = _run(cmd)
        print(out)
        sys.exit(code)

# ---- HTTP mode ----
def _maybe_fastapi():
    try:
        from fastapi import FastAPI
        from pydantic import BaseModel, field_validator
        import uvicorn
    except Exception:
        return None

    app = FastAPI(title="Auto SSL API")

    class AddDomainBody(BaseModel):
        domain: str
        target: str | None = None

        @field_validator("domain")
        @classmethod
        def _v_domain(cls, v: str):
            if "." not in v:
                raise ValueError("Invalid domain")
            return v.lower()

    @app.post("/api/add-domain")
    def add_domain(body: AddDomainBody):
        res = add_or_update_domain(body.domain, body.target)
        return res

    return app

if __name__ == "__main__":
    if len(sys.argv) > 1:
        _cli()
    else:
        app = _maybe_fastapi()
        if app is None:
            print("FastAPI not installed. Use CLI mode.")
            sys.exit(1)
        import uvicorn
        uvicorn.run("auto_ssl:app", host="0.0.0.0", port=int(os.getenv("PORT", "5001")), reload=False)
