FROM debian:12

# Install dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    python3 python3-pip \
    lua-nginx-module \
    certbot \
    python3-certbot-nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps
COPY requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# Copy config supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy nginx config & Python API
COPY nginx.conf /etc/nginx/nginx.conf
COPY app /app

WORKDIR /app

# Expose ports
EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
