local cjson = require("cjson.safe")
local domains = ngx.shared.domains
local host = ngx.var.host

if not host or host == "" then
  return ngx.exit(444)
end

local target = domains:get(host)

if not target then
  local f = io.open("/etc/nginx/domains.json", "r")
  if f then
    local content = f:read("*a"); f:close()
    local data = cjson.decode(content) or {}
    target = data[host]
    if target then domains:set(host, target) end
  end
end

if not target then
  ngx.status = 404
  ngx.say("Domain not registered: ", host)
  return ngx.exit(ngx.HTTP_NOT_FOUND)
end

ngx.var.upstream = target
