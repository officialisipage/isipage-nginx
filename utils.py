# utils.py
import os
import json
import shutil

def read_domains(path="/etc/nginx/domains.json"):
    try:
        if not os.path.exists(path):
            return {}
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def write_domains(path, data):
    dirp = os.path.dirname(path)
    if dirp and not os.path.exists(dirp):
        os.makedirs(dirp, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def generate_domains_map(domains_dict, map_path="/etc/nginx/conf.d/domains.map"):
    lines = []
    for d, t in domains_dict.items():
        lines.append(f"{d} {t};")
    content = "\n".join(lines) + "\n"
    dirp = os.path.dirname(map_path)
    if dirp and not os.path.exists(dirp):
        os.makedirs(dirp, exist_ok=True)
    with open(map_path, "w") as f:
        f.write(content)
    return True

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def copy_cert_from_letsencrypt(domain, letsencrypt_live="/etc/letsencrypt/live", nginx_ssl_base="/etc/nginx/ssl"):
    src = os.path.join(letsencrypt_live, domain)
    if not os.path.exists(src):
        return False, f"source not found: {src}"
    src_full = os.path.join(src, "fullchain.pem")
    src_priv = os.path.join(src, "privkey.pem")
    if not (os.path.exists(src_full) and os.path.exists(src_priv)):
        return False, "cert files missing in letsencrypt live"
    dst = os.path.join(nginx_ssl_base, domain)
    os.makedirs(dst, exist_ok=True)
    try:
        shutil.copy2(src_full, os.path.join(dst, "fullchain.pem"))
        shutil.copy2(src_priv, os.path.join(dst, "privkey.pem"))
        return True, f"copied to {dst}"
    except Exception as e:
        return False, str(e)
