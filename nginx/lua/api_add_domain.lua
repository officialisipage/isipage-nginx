local cjson = require "cjson.safe"
local domains = ngx.shared.domains

-- Ambil body JSON (kalau ada) + query
ngx.req.read_body()
local body = ngx.req.get_body_data()
local data = body and cjson.decode(body) or {}

local args = ngx.req.get_uri_args() or {}

local domain = (data and data.domain) or args["domain"]
local target = (data and data.target) or args["target"] or "103.250.11.31:2000"

if not domain or not domain:find("%.") then
  ngx.status = 400
  ngx.say("❌ Invalid/missing domain")
  return
end

-- Update cache
domains:set(domain, target)

-- Atomic write domains.json
local filepath = "/etc/nginx/domains.json"
local content = "{}"
do
  local f = io.open(filepath, "r")
  if f then content = f:read("*a"); f:close() end
end
local ok, data_json = pcall(cjson.decode, content)
if not ok or type(data_json) ~= "table" then data_json = {} end
data_json[domain] = target

local tmp = filepath .. ".tmp"
do
  local wf = io.open(tmp, "w")
  if not wf then
    ngx.status = 500
    ngx.say("❌ Cannot open temp domains file")
    return
  end
  wf:write(cjson.encode(data_json))
  wf:close()
end
os.execute(string.format("mv %q %q && chmod 664 %q && chgrp nginx %q 2>/dev/null || true", tmp, filepath, filepath, filepath))

-- Jalankan Certbot async + perbaiki permission + reload
local function run_certbot(premature, dom)
  if premature then return end

  local tmpfile  = "/tmp/certbot_output.txt"
  local cert_dir = "/var/lib/certbot"

  local cmd = string.format(
    "certbot certonly --webroot -w /var/www/certbot -d %q --non-interactive --agree-tos -m admin@%s --expand --logs-dir /tmp --work-dir /tmp --config-dir %q --no-permissions-check > %s 2>&1",
    dom, dom, cert_dir, tmpfile
  )

  os.execute(cmd)

  -- Fix perms jika sukses
  local full = cert_dir .. "/live/" .. dom .. "/fullchain.pem"
  local key  = cert_dir .. "/live/" .. dom .. "/privkey.pem"

  local f1 = io.open(full, "r")
  local f2 = io.open(key, "r")
  if f1 and f2 then
    f1:close(); f2:close()
    os.execute(string.format("chgrp nginx %q %q 2>/dev/null || true", full, key))
    os.execute(string.format("chmod 644 %q 2>/dev/null || true", full))
    os.execute(string.format("chmod 640 %q 2>/dev/null || true", key))
    os.execute("nginx -s reload")
    ngx.log(ngx.INFO, "✅ Cert issued & nginx reloaded for " .. dom)
  else
    local fo = io.open(tmpfile, "r")
    local out = fo and fo:read("*a") or "(no output)"
    if fo then fo:close() end
    ngx.log(ngx.ERR, "❌ Certbot failed for " .. dom .. "\\n" .. out)
  end
end

ngx.timer.at(0.01, run_certbot, domain)

ngx.status = 200
ngx.say("🕓 Certbot diproses background untuk: ", domain, " → ", target)
