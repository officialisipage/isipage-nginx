local cjson = require "cjson.safe"
local domains = ngx.shared.domains

ngx.req.read_body()
local body = ngx.req.get_body_data()
local data = (body and cjson.decode(body)) or {}

local args = ngx.req.get_uri_args() or {}
local domain = (data and data.domain) or args.domain
local target = (data and data.target) or args.target or "103.250.11.31:2000"

if not domain or not domain:find("%.") then
  ngx.status = 400
  ngx.say("❌ Invalid or missing domain")
  return
end

-- Cache di shared dict
domains:set(domain, target)

-- Update file JSON (atomic write)
local filepath = "/etc/nginx/domains.json"
local f = io.open(filepath, "r")
local content = f and f:read("*a") or "{}"
if f then f:close() end
local ok, map = pcall(cjson.decode, content); if not ok or type(map) ~= "table" then map = {} end
map[domain] = target

local tmp = filepath .. ".tmp"
local wf = assert(io.open(tmp, "w"))
wf:write(cjson.encode(map))
wf:close()
os.rename(tmp, filepath)

-- Jalankan Certbot async
local function run_certbot(premature, domain)
  if premature then return end
  local cert_dir = "/var/lib/certbot"
  local logf = "/tmp/certbot_output.txt"
  local cmd = "certbot certonly --webroot -w /var/www/certbot -d " .. domain ..
      " --non-interactive --agree-tos -m admin@" .. domain ..
      " --expand --logs-dir /tmp --work-dir /tmp --config-dir " .. cert_dir ..
      " --no-permissions-check > " .. logf .. " 2>&1"

  os.execute(cmd)

  local live = cert_dir .. "/live/" .. domain
  local fc = io.open(live .. "/fullchain.pem", "r")
  local fk = io.open(live .. "/privkey.pem", "r")
  if fc and fk then
    fc:close(); fk:close()
    -- Perbaiki permission agar Nginx bisa baca kuncinya
    os.execute("chgrp -R nginx " .. live .. " 2>/dev/null || true")
    os.execute("chmod 644 " .. live .. "/fullchain.pem 2>/dev/null || true")
    os.execute("chmod 640 " .. live .. "/privkey.pem 2>/dev/null || true")
    os.execute("nginx -s reload")
    ngx.log(ngx.INFO, "✅ Cert issued & nginx reloaded for " .. domain)
  else
    local lf = io.open(logf, "r"); local out = lf and lf:read("*a") or "(no output)"; if lf then lf:close() end
    ngx.log(ngx.ERR, "❌ Certbot failed for " .. domain .. "\\n" .. out)
  end
end

ngx.timer.at(0.1, run_certbot, domain)

ngx.status = 200
ngx.say("🕓 Cerbot diproses background untuk: ", domain, " → ", target)
