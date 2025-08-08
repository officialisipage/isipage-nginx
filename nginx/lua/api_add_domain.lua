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

local filepath = "/etc/nginx/domains.json"
local content = "{}"
local file = io.open(filepath, "r")
if file then
    content = file:read("*a")
    file:close()
end


local ok, data = pcall(cjson.decode, content)
if not ok then data = {} end
data[domain] = target

file = io.open(filepath, "w+")
file:write(cjson.encode(data))
file:close()

local cmd = "certbot certonly --webroot -w /var/www/certbot -d " .. domain ..
            " --non-interactive --agree-tos -m admin@" .. domain .. " --expand"
local handle = io.popen(cmd)
local output = handle:read("*a")
handle:close()

local test_cert = io.open("/etc/letsencrypt/live/" .. domain .. "/fullchain.pem", "r")
if not test_cert then
  ngx.status = 500
  ngx.say("❌ Certbot failed:\n", output)
  return
end
test_cert:close()

os.execute("nginx -s reload")

ngx.status = 200
ngx.say("✅ Domain added and SSL ready: ", domain)
