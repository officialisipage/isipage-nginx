local json = require("cjson")
local domains = ngx.shared.domains

local domain = ngx.var.arg.domain
local target = ngx.var.arg.target or "103.250.11.31:2000"

if not domain then
    ngx.status = 400
    ngx.say("Missing 'domain' parameter")
    return
end

-- Simpan ke shared memory
domains:set(domain, target)

-- Baca file JSON lama
local filepath = "/etc/nginx/domains.json"
local file = io.open(filepath, "r")
local content = file and file:read("*a") or "{}"
if file then file:close() end

local ok, data = pcall(json.decode, content)
if not ok then data = {} end

-- Update & tulis ulang
data[domain] = target
file = io.open(filepath, "w+")
file:write(json.encode(data))
file:close()

ngx.status = 200
ngx.say("✅ Domain saved: " .. domain .. " → " .. target)
