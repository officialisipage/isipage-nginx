local dict = ngx.shared.domains -- sudah kamu deklar di nginx.conf
local CERTBOT = "/usr/bin/certbot"
local CERT_DIR = "/var/lib/certbot"
local LOGS_DIR = CERT_DIR .. "/logs"
local WORK_DIR = CERT_DIR .. "/work"
os.execute("mkdir -p " .. LOGS_DIR .. " " .. WORK_DIR)

-- ---- LOCK per domain ----
local function acquire_lock(d)
  local key = "certbot_lock:" .. d
  local ok = dict:add(key, 1, 120)  -- lock 120 detik
  return ok, key
end

local function release_lock(key) dict:delete(key) end

-- ---- tulis domains.json secara atomic ----
local function upsert_domain_json(d, target)
  local path = "/etc/nginx/domains.json"
  local tmp  = path .. ".tmp"

  local json = require "cjson.safe"
  local map = {}
  do
    local f = io.open(path, "r")
    if f then map = json.decode(f:read("*a") or "{}") or {}; f:close() end
  end
  map[d] = target

  local f = assert(io.open(tmp, "w"))
  f:write(json.encode(map) or "{}")
  f:close()
  os.execute("mv -f " .. tmp .. " " .. path)
end

-- ---- jalankan certbot asinkron ----
local function run_certbot(premature, d)
  if premature then return end

  local logf = LOGS_DIR .. "/certbot_" .. d .. ".log"
  local cmd = table.concat({
    CERTBOT, "certonly",
    "--webroot", "-w", "/var/www/certbot",
    "-d", d,
    "--non-interactive", "--agree-tos", "-m", "admin@"..d,
    "--config-dir", CERT_DIR,
    "--work-dir", WORK_DIR,
    "--logs-dir", LOGS_DIR,
    -- "--staging", -- untuk uji
  }, " ")

  -- jalankan dan simpan output
  cmd = cmd .. " > " .. logf .. " 2>&1"
  local rc = os.execute(cmd)

  -- set permission untuk Nginx membaca
  local live = CERT_DIR .. "/live/" .. d
  os.execute("chgrp nginx " .. live .. "/fullchain.pem " .. live .. "/privkey.pem 2>/dev/null || true")
  os.execute("chmod 644 " .. live .. "/fullchain.pem 2>/dev/null || true")
  os.execute("chmod 640 " .. live .. "/privkey.pem 2>/dev/null || true")

  -- TIDAK PERLU nginx -s reload untuk ssl_certificate_by_lua_block
  release_lock("certbot_lock:"..d)
end

-- ==== handler utama ====
local d = domain
local ok, lock_key = acquire_lock(d)
if not ok then
  return ngx.say('{"ok":false,"message":"Certbot for this domain is in progress"}')
end

upsert_domain_json(d, target)
ngx.timer.at(0.05, run_certbot, d)

ngx.header["Content-Type"] = "application/json"
ngx.say('{"ok":true,"message":"Saved & certbot started","domain":"'..d..'"}')
