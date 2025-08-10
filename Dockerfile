FROM openresty/openresty:alpine

# install sistem deps
RUN apk add --no-cache python3 py3-pip bash curl certbot openssl jq

# buat virtualenv untuk Python
RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"

# install python deps di virtualenv
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# buat direktori
RUN mkdir -p /etc/nginx/conf.d /etc/nginx/ssl /var/www/certbot /app /var/log/letsencrypt /tmp/dummy_certs

# copy app + nginx conf + assets
COPY app.py /app/app.py
COPY utils.py /app/utils.py
COPY nginx.conf /etc/nginx/nginx.conf
COPY domains.json /etc/nginx/domains.json
COPY www /var/www
COPY requirements.txt /app/requirements.txt

WORKDIR /app

# generate dummy certs sehingga OpenResty bisa start
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -subj "/CN=dummy" -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt

# izin untuk webroot & cert dirs
RUN chmod -R 777 /var/www/certbot /etc/nginx/ssl || true

EXPOSE 80 443 5000

# jalankan Flask API di background lalu OpenResty di foreground
CMD ["sh", "-c", "python /app/app.py & /usr/local/openresty/bin/openresty -g 'daemon off;'"]
