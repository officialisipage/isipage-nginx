local cjson = require "cjson.safe"
local dict  = ngx.shared.domains

-- ===== Helper: baca body JSON =====
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

-- ===== Helper: atomic write domains.json =====
local function upsert_domain(filepath, domain, target)
  local json = require "cjson.safe"
  local map = {}
  do
    local f = io.open(filepath, "r")
    if f then
      map = json.decode(f:read("*a") or "{}") or {}
      f:close()
    end
  end
  map[domain] = target
  local out = json.encode(map) or "{}"

  local tmp = filepath .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  f:write(out)
  f:close()
  os.execute("mv -f " .. tmp .. " " .. filepath)
end

-- ===== Helper: simple lock per-domain (120s) =====
local function acquire_lock(d)
  if not dict then return true, nil end
  local key = "certbot_lock:" .. d
  local ok = dict:add(key, 1, 120)
  return ok, key
end

local function release_lock(key)
  if dict and key then dict:delete(key) end
end

-- ===== Async certbot runner =====
local function run_certbot(premature, d)
  if premature then return end

  local CERTBOT   = "/usr/bin/certbot"  -- absolute path
  local CERT_DIR  = "/var/lib/certbot"
  local LOGS_DIR  = CERT_DIR .. "/logs"
  local WORK_DIR  = CERT_DIR .. "/work"
  os.execute("mkdir -p " .. LOGS_DIR .. " " .. WORK_DIR)

  local logf = LOGS_DIR .. "/certbot_" .. d .. ".log"

  local cmd = table.concat({
    CERTBOT, "certonly",
    "--webroot", "-w", "/var/www/certbot",
    "-d", d,
    "--non-interactive", "--agree-tos", "-m", "admin@"..d,
    "--config-dir", CERT_DIR,
    "--work-dir", WORK_DIR,
    "--logs-dir", LOGS_DIR
  }, " ")

  -- redirect ke log file
  cmd = cmd .. " > " .. logf .. " 2>&1"

  -- jalankan certbot
  os.execute(cmd)

  -- set permission agar Nginx bisa baca
  local live = CERT_DIR .. "/live/" .. d
  os.execute("chgrp nginx " .. live .. "/fullchain.pem " .. live .. "/privkey.pem 2>/dev/null || true")
  os.execute("chmod 644 " .. live .. "/fullchain.pem 2>/dev/null || true")
  os.execute("chmod 640 " .. live .. "/privkey.pem 2>/dev/null || true")

  ngx.log(ngx.INFO, "✅ Certbot finished for " .. d)
end

-- ===== Simpan domains.json (atomic) + update cache =====
local filepath = "/etc/nginx/domains.json"
upsert_domain(filepath, domain, target)
if dict then dict:set(domain, target) end

-- ===== Lock supaya tidak balapan =====
local ok_lock, lock_key = acquire_lock(domain)
if not ok_lock then
  ngx.status = 409
  ngx.header["Content-Type"] = "application/json"
  ngx.say(cjson.encode({ ok=false, message="Certbot for this domain is already in progress" }))
  return
end

-- ===== Jalanin certbot async =====
local ok, err = ngx.timer.at(0.05, function(premature)
  local ok2, err2 = pcall(run_certbot, premature, domain)
  release_lock(lock_key)
  if not ok2 then
    ngx.log(ngx.ERR, "❌ Certbot error for " .. domain .. ": " .. (err2 or "?"))
  end
end)
if not ok then
  release_lock(lock_key)
  ngx.status = 500
  ngx.say(cjson.encode({ ok=false, message="Failed to start certbot: "..(err or "?") }))
  return
end

-- ===== Response =====
ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({ ok=true, message="Saved & certbot started", domain=domain, target=target }))
