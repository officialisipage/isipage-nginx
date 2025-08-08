local cjson = require "cjson"
local domains = ngx.shared.domains

-- === PARAMETER ===
local args = ngx.req.get_uri_args()
local domain = args["domain"]
local target = args["target"] or "103.250.11.31:2000"

if not domain then
  ngx.status = 400
  ngx.say("❌ Missing domain parameter")
  return
end

-- === SIMPAN KE SHARED MEMORY ===
domains:set(domain, target)

-- === SIMPAN KE FILE domains.json ===
local filepath = "/etc/nginx/domains.json"
local content = "{}"

local f = io.open(filepath, "r")
if f then
  content = f:read("*a")
  f:close()
end

local ok, data = pcall(cjson.decode, content)
if not ok then data = {} end

data[domain] = target

local wf = io.open(filepath, "w+")
if wf then
  wf:write(cjson.encode(data))
  wf:close()
else
  ngx.status = 500
  ngx.say("❌ Gagal menulis ke domains.json")
  return
end

-- === JALANKAN CERTBOT ===
local tmpfile = "/tmp/certbot_output.txt"
local cert_dir = "/var/lib/certbot"
local webroot = "/var/www/certbot"
local certbot_bin = "/usr/bin/certbot"  -- Sesuaikan path jika perlu

local cmd = string.format(
  'sudo %s certonly --webroot -w %s -d %s --non-interactive --agree-tos -m admin@%s --expand --logs-dir /tmp --work-dir /tmp --config-dir %s',
  certbot_bin, webroot, domain, domain, cert_dir
)

local full_cmd = cmd .. " > " .. tmpfile .. " 2>&1"

ngx.log(ngx.ERR, "[CERTBOT CMD] ", full_cmd)

-- Execute certbot
local result = os.execute(full_cmd)

-- Read certbot output
local fo = io.open(tmpfile, "r")
local output = fo and fo:read("*a") or "(no output)"
if fo then fo:close() end

ngx.log(ngx.ERR, "[CERTBOT OUTPUT] ", output)
ngx.log(ngx.ERR, "[CERTBOT EXIT CODE] ", tostring(result))

-- === CEK BERHASIL? ===
local cert_path = cert_dir .. "/live/" .. domain .. "/fullchain.pem"
local test_cert = io.open(cert_path, "r")

if not test_cert then
  ngx.status = 500
  ngx.say("❌ Certbot failed for: ", domain, "\n\nOutput:\n", output)
  return
end
test_cert:close()

-- ✅ SUCCESS (tanpa reload nginx)
ngx.status = 200
ngx.say("✅ Domain added and SSL ready: ", domain)
