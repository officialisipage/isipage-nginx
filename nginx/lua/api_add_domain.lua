local cjson = require "cjson.safe"
local function read_body_json()
  ngx.req.read_body()
  local b = ngx.req.get_body_data()
  if not b or b == "" then return {} end
  return cjson.decode(b) or {}
end

local data = read_body_json()
local args = ngx.req.get_uri_args() or {}

local domain = (data.domain or args.domain or "")
local target = (data.target or args.target or "103.250.11.31:2000")

if domain == "" or not domain:find("%.") then
  ngx.status = 400
  ngx.say(cjson.encode({ ok=false, message="Invalid domain" }))
  return
end

-- path domains.json
local filepath = "/etc/nginx/domains.json"

-- pastikan file ada & bisa dibaca
local content = "{}"
do
  local f = io.open(filepath, "r")
  if f then content = f:read("*a") or "{}"; f:close() end
end

-- parse & update map
local ok, map = pcall(cjson.decode, content)
if not ok or type(map) ~= "table" then map = {} end
map[domain] = target
local out = cjson.encode(map)

-- TULIS LANGSUNG TANPA .tmp
do
  -- coba buka r+ (edit in-place). kalau belum ada, fallback w+
  local f = io.open(filepath, "r+")
  if not f then f = io.open(filepath, "w+") end
  if not f then
    ngx.status = 500
    ngx.say(cjson.encode({ ok=false, message="Cannot open domains.json for write" }))
    return
  end
  f:seek("set", 0)
  f:write(out)
  f:flush()
  -- kalau file sebelumnya lebih panjang, truncate biar bersih
  local len = #out
  pcall(function() f:seek("set", len); f:write(""); end)
  f:close()
end

-- update cache ringan (opsional)
local dict = ngx.shared.domains
if dict then dict:set(domain, target) end

-- jalankan certbot async
-- jalankan certbot async
local function run_certbot(premature, d)
  if premature then return end

  -- cek siapa yang menjalankan
  local whoami_output = "/tmp/whoami_certbot.txt"
  os.execute("whoami > " .. whoami_output)
  local wf = io.open(whoami_output, "r")
  local who = wf and wf:read("*l") or "(unknown)"
  if wf then wf:close() end
  ngx.log(ngx.NOTICE, "Certbot dijalankan oleh user: " .. who)

  local cert_dir = "/var/lib/certbot"
  local logs_dir = cert_dir .. "/logs"
  local work_dir = cert_dir .. "/work"
  os.execute("mkdir -p " .. logs_dir .. " " .. work_dir)

  os.execute("chmod -R 777 " .. cert_dir .. " 2>/dev/null || true")
  local logf = logs_dir .. "/certbot_output_" .. d .. ".txt"

  local cmd = string.format(
    "/bin/sh -c '/usr/bin/certbot -v certonly --webroot -w /var/www/certbot -d %s " ..
    "--non-interactive --agree-tos -m admin@%s --config-dir %s --work-dir %s --logs-dir %s " ..
    "--cert-name %s > %s 2>&1'",
    d, d, cert_dir, work_dir, logs_dir, d, logf
  )

  local rc = os.execute(cmd)

  -- cek hasil issuance
  local live = cert_dir .. "/live/" .. d
  local full = live .. "/fullchain.pem"
  local key  = live .. "/privkey.pem"

  local fc = io.open(full, "r")
  local fk = io.open(key, "r")
  if fc and fk then
    fc:close(); fk:close()
    os.execute("/usr/local/openresty/nginx/sbin/nginx -t >/dev/null 2>&1 && /usr/local/openresty/nginx/sbin/nginx -s reload")
    ngx.log(ngx.NOTICE, "Cert issued & nginx reloaded for " .. d)
  else
    local f = io.open(logf, "r"); local out = f and f:read("*a") or "(no output)"; if f then f:close() end
    ngx.log(ngx.ERR, "Certbot failed for " .. d .. "\n" .. out)
  end
end


ngx.timer.at(0.05, run_certbot, domain)

ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({ ok=true, message="Saved & certbot started", domain=domain, target=target }))

