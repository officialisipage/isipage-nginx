local cjson = require "cjson.safe"

-- Log user yang menjalankan proses
do
  local f = io.popen("whoami")
  local who = f:read("*l") or "(unknown)"
  f:close()
  ngx.log(ngx.ERR, "[WHOAMI] Script /api/add-domain dijalankan oleh user: " .. who)
end

-- Baca body JSON
local function read_body_json()
  ngx.req.read_body()
  local b = ngx.req.get_body_data()
  return (b and b ~= "" and cjson.decode(b)) or {}
end

local data, args = read_body_json(), ngx.req.get_uri_args() or {}
local domain = data.domain or args.domain or ""
local target = data.target or args.target or "103.250.11.31:2000"

if domain == "" or not domain:find("%.") then
  return ngx.status = 400, ngx.say(cjson.encode({ ok = false, message = "Invalid domain" }))
end

-- Update domains.json
local filepath = "/etc/nginx/domains.json"
local map = (function()
  local f = io.open(filepath, "r")
  local content = f and f:read("*a") or "{}"
  if f then f:close() end
  return cjson.decode(content) or {}
end)()

map[domain] = target
local f = io.open(filepath, "w+")
if not f then
  return ngx.status = 500, ngx.say(cjson.encode({ ok = false, message = "Cannot open domains.json for write" }))
end
f:write(cjson.encode(map))
f:close()

-- Update cache shared dict
local dict = ngx.shared.domains
if dict then dict:set(domain, target) end

-- Jalankan certbot async
ngx.timer.at(0, function(_, d)
  local cert_dir, logs_dir, work_dir = "/var/lib/certbot", "/var/lib/certbot/logs", "/var/lib/certbot/work"
  os.execute(("mkdir -p %s %s && chmod -R 777 %s"):format(logs_dir, work_dir, cert_dir))
  local logf = ("%s/certbot_output_%s.txt"):format(logs_dir, d)

  local cmd = string.format(
    "/usr/bin/certbot certonly --webroot -w /var/www/certbot -d %s " ..
    "--non-interactive --agree-tos -m admin@%s --config-dir %s --work-dir %s --logs-dir %s " ..
    "--cert-name %s > %s 2>&1",
    d, d, cert_dir, work_dir, logs_dir, d, logf
  )
  os.execute(cmd)

  local live = cert_dir .. "/live/" .. d
  local fc, fk = io.open(live .. "/fullchain.pem"), io.open(live .. "/privkey.pem")
  if fc and fk then
    fc:close(); fk:close()
    os.execute("/usr/local/openresty/nginx/sbin/nginx -t >/dev/null 2>&1 && /usr/local/openresty/nginx/sbin/nginx -s reload")
    ngx.log(ngx.NOTICE, "Cert issued & nginx reloaded for " .. d)
  else
    local lf = io.open(logf, "r")
    ngx.log(ngx.ERR, "Certbot failed for " .. d .. "\n" .. ((lf and lf:read("*a")) or "(no output)"))
    if lf then lf:close() end
  end
end, domain)

ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({ ok = true, message = "Saved & certbot started", domain = domain, target = target }))
