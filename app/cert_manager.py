import subprocess
import os

def generate_ssl(domain: str, ssl_path: str):
    """
    Request SSL from Let's Encrypt and store in /etc/nginx/ssl/{domain}/
    """
    print(f"[SSL] Generating SSL for {domain}")
    acme_dir = "/var/www/certbot"

    # Request certificate
    cmd = [
        "certbot", "certonly", "--webroot", "-w", acme_dir,
        "-d", domain, "--non-interactive", "--agree-tos",
        "--email", "admin@" + domain, "--force-renewal"
    ]
    subprocess.run(cmd, check=True)

    # Move certs to custom path
    live_path = f"/etc/letsencrypt/live/{domain}"
    if os.path.exists(live_path):
        os.system(f"cp {live_path}/fullchain.pem {ssl_path}/fullchain.pem")
        os.system(f"cp {live_path}/privkey.pem {ssl_path}/privkey.pem")
        print(f"[SSL] Certificate stored in {ssl_path}")
    else:
        raise Exception(f"Let's Encrypt certs not found for {domain}")
