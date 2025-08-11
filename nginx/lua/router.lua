local cjson = require "cjson.safe"
local host = ngx.var.host

if not host or host == "" then
  return ngx.exit(444)
end

local f = io.open("/etc/nginx/domains.json", "r")
if not f then
  ngx.log(ngx.ERR, "domains.json not found")
  return ngx.exit(444)
end
local content = f:read("*a"); f:close()
local map = cjson.decode(content) or {}
local upstream = map[host]

if not upstream or upstream == "" then
  ngx.log(ngx.WARN, "No upstream for host " .. host)
  return ngx.exit(444)
end

ngx.var.upstream = upstream
