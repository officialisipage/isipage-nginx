FROM python:3.11-alpine
RUN apk add --no-cache certbot
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY auto_ssl.py .
ENV PORT=5001
CMD ["python", "auto_ssl.py"]
