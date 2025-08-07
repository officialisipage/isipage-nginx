local cjson = require "cjson"
local dict = ngx.shared.domain_backends

ngx.req.read_body()
local body = ngx.req.get_body_data()

local ok, data = pcall(cjson.decode, body)
if not ok then
    ngx.status = 400
    ngx.say("Invalid JSON")
    return
end

local domain = data.domain
local backend = data.backend

if not domain or not backend then
    ngx.status = 400
    ngx.say("Missing 'domain' or 'backend'")
    return
end

-- Simpan ke shared dictionary
dict:set(domain, backend)

ngx.status = 200
ngx.say("✅ Registered: ", domain, " → ", backend)
