local cjson = require "cjson"
local domains = ngx.shared.domains

local args = ngx.req.get_uri_args()
local domain = args["domain"]
local target = args["target"] or "103.250.11.31:2000"

if not domain then
  ngx.status = 400
  ngx.say("❌ Missing domain parameter")
  return
end

-- Simpan ke shared memory
domains:set(domain, target)

-- Baca file domains.json (jika ada)
local filepath = "/etc/nginx/domains.json"
local content = "{}"

local f = io.open(filepath, "r")
if f then
  content = f:read("*a")
  f:close()
end

-- Decode atau fallback ke tabel kosong
local ok, data = pcall(cjson.decode, content)
if not ok then data = {} end

-- Tambah domain ke mapping
data[domain] = target

-- Simpan ulang ke file
local wf = io.open(filepath, "w+")
if wf then
  wf:write(cjson.encode(data))
  wf:close()
else
  ngx.status = 500
  ngx.say("❌ Gagal menulis ke domains.json")
  return
end

-- Jalankan certbot (redirect output ke file agar bisa dibaca Lua)
local tmpfile = "/tmp/certbot_output.txt"
local cmd = "certbot certonly --webroot -w /var/www/certbot -d " .. domain ..
  " --non-interactive --agree-tos -m admin@" .. domain ..
  " --expand --logs-dir /tmp --work-dir /tmp --config-dir /tmp/certbot-config"
local full_cmd = cmd .. " > " .. tmpfile .. " 2>&1"
os.execute(full_cmd)

-- Baca hasil output certbot
local f = io.open(tmpfile, "r")
local output = f and f:read("*a") or "(no output)"
if f then f:close() end

-- Cek apakah cert berhasil
local cert_path = "/etc/letsencrypt/live/" .. domain .. "/fullchain.pem"
local test_cert = io.open(cert_path, "r")
if not test_cert then
  ngx.status = 500
  ngx.say("❌ Certbot failed. Output:\n", output)
  return
end
test_cert:close()

-- Reload nginx
os.execute("nginx -s reload")

ngx.status = 200
ngx.say("✅ Domain added and SSL ready: ", domain)
