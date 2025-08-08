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

domains:set(domain, target)

-- Update file JSON
local filepath = "/etc/nginx/domains.json"
local content = "{}"

do
  local f = io.open(filepath, "r")
  if f then
    content = f:read("*a")
    f:close()
  end
end

local ok, data = pcall(cjson.decode, content)
if not ok then data = {} end
data[domain] = target

do
  local wf = io.open(filepath, "w+")
  if wf then
    wf:write(cjson.encode(data))
    wf:close()
  else
    ngx.status = 500
    ngx.say("❌ Failed to write domains.json")
    return
  end
end

-- ✅ Run certbot + reload async
local function run_certbot(premature, domain, target)
  if premature then return end

  local tmpfile = "/tmp/certbot_output.txt"
  local cert_dir = "/var/lib/certbot"
  local cmd = "certbot certonly --webroot -w /var/www/certbot -d " .. domain ..
    " --non-interactive --agree-tos -m admin@" .. domain ..
    " --expand --logs-dir /tmp --work-dir /tmp --config-dir " .. cert_dir ..
    " > " .. tmpfile .. " 2>&1"

  os.execute(cmd)

  local cert_path = cert_dir .. "/live/" .. domain .. "/fullchain.pem"
  local test = io.open(cert_path, "r")
  if test then
    test:close()
    ngx.log(ngx.INFO, "✅ Certbot success for " .. domain)
    os.execute("nginx -s reload")
  else
    local f = io.open(tmpfile, "r")
    local output = f and f:read("*a") or "(no output)"
    if f then f:close() end
    ngx.log(ngx.ERR, "❌ Certbot failed for " .. domain .. "\n" .. output)
  end
end

-- Jalankan certbot async
ngx.timer.at(0.1, run_certbot, domain, target)

-- ✅ Kirim response langsung ke client
ngx.status = 200
ngx.say("🕓 Certbot sedang diproses di background untuk: ", domain)
