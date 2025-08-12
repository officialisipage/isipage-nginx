local cjson = require "cjson.safe"

ngx.req.read_body()
local body = ngx.req.get_body_data()
local data = (body and cjson.decode(body)) or {}
local args = ngx.req.get_uri_args() or {}

local domain = (data and data.domain) or args.domain
local target = (data and data.target) or args.target or "103.250.11.31:2000"

if not domain or not domain:find("%.") then
  ngx.status = 400
  ngx.say(cjson.encode({ ok=false, message="Invalid domain" }))
  return
end

-- baca peta lama
local path = "/etc/nginx/domains.json"
local old = "{}"
do
  local f = io.open(path, "r")
  if f then old = f:read("*a") or "{}"; f:close() end
end
local ok, map = pcall(cjson.decode, old)
if not ok or type(map) ~= "table" then map = {} end
map[domain] = target

-- tulis atomic
local tmp = path .. ".tmp"
local wf = assert(io.open(tmp, "w"))
wf:write(cjson.encode(map))
wf:close()
os.rename(tmp, path)

-- certbot async
local function run_certbot(premature, d)
  if premature then return end
  local cert_dir = "/var/lib/certbot"
  local logf = "/tmp/certbot_output.txt"
  local cmd = "certbot certonly --webroot -w /var/www/certbot -d " .. d ..
      " --non-interactive --agree-tos -m admin@" .. d ..
      " --expand --logs-dir /tmp --work-dir /tmp --config-dir " .. cert_dir ..
      " --no-permissions-check > " .. logf .. " 2>&1"
  os.execute(cmd)

  local live = cert_dir .. "/live/" .. d
  local fc = io.open(live .. "/fullchain.pem", "r")
  local fk = io.open(live .. "/privkey.pem", "r")
  if fc and fk then
    fc:close(); fk:close()
    os.execute("addgroup -S nginx 2>/dev/null || true")
    os.execute("chgrp -R nginx " .. live .. " 2>/dev/null || true")
    os.execute("chmod 644 " .. live .. "/fullchain.pem 2>/dev/null || true")
    os.execute("chmod 640 " .. live .. "/privkey.pem 2>/dev/null || true")
    os.execute("nginx -s reload")
    ngx.log(ngx.INFO, "Cert issued & nginx reloaded for " .. d)
  else
    local lf = io.open(logf, "r"); local out = lf and lf:read("*a") or "(no output)"; if lf then lf:close() end
    ngx.log(ngx.ERR, "Certbot failed for " .. d .. "\\n" .. out)
  end
end

ngx.timer.at(0.05, run_certbot, domain)

ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({ ok=true, message="Certbot started", domain=domain, target=target }))
