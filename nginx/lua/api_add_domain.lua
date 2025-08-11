local cjson = require "cjson.safe"
local domains = ngx.shared.domains

ngx.req.read_body()
local body = cjson.decode(ngx.req.get_body_data() or "") or {}
local args = ngx.req.get_uri_args() or {}

local domain = (body.domain or args.domain or ""):lower()
local target = body.target or args.target or "103.250.11.31:2000"

if domain == "" or not string.find(domain, "%.") then
  ngx.status = 400
  ngx.say(cjson.encode({ ok=false, message="Invalid domain" }))
  return
end

domains:set(domain, target)

-- Atomic write to /etc/nginx/domains.json
local path = "/etc/nginx/domains.json"
local old = "{}"
do
  local f = io.open(path, "r")
  if f then old = f:read("*a"); f:close() end
end
local data = cjson.decode(old) or {}
data[domain] = target

local tmp = path .. ".tmp"
local f = io.open(tmp, "w")
if not f then
  ngx.status = 500
  ngx.say(cjson.encode({ ok=false, message="Failed to write temp file" }))
  return
end
f:write(cjson.encode(data)); f:close()
os.execute(string.format("mv -f %q %q && chgrp nginx %q && chmod 664 %q", tmp, path, path, path))

-- Certbot async issuance
local function run_certbot(premature, d)
  if premature then return end
  local cert_dir = "/var/lib/certbot"
  local webroot = "/var/www/certbot"
  local email = "admin@" .. d
  local out = "/tmp/certbot_output.txt"

  local cmd = string.format([[certbot certonly --webroot -w %s -d %s --non-interactive --agree-tos -m %s --expand --logs-dir /tmp --work-dir /tmp --config-dir %s --no-permissions-check > %s 2>&1]],
    webroot, d, email, cert_dir, out)
  os.execute(cmd)

  local live = cert_dir .. "/live/" .. d
  local key = live .. "/privkey.pem"
  local crt = live .. "/fullchain.pem"
  os.execute("chgrp nginx " .. key .. " " .. crt .. " 2>/dev/null || true")
  os.execute("chmod 640 " .. key .. " 2>/dev/null || true")
  os.execute("chmod 644 " .. crt .. " 2>/dev/null || true")

  local t = io.open(crt, "r")
  if t then
    t:close()
    ngx.log(ngx.INFO, "Certbot success for " .. d)
    os.execute("nginx -s reload")
  else
    local f = io.open(out, "r")
    local log = f and f:read("*a") or "(no output)"
    if f then f:close() end
    ngx.log(ngx.ERR, "Certbot failed for " .. d .. "\n" .. log)
  end
end

ngx.timer.at(0.01, run_certbot, domain)

ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({ ok=true, message="Certbot running in background", domain=domain, target=target }))
