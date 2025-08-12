-- /etc/nginx/lua/router.lua
local cjson = require "cjson.safe"

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local s = f:read("*a") or ""
  f:close()
  local t = cjson.decode(s)
  if type(t) ~= "table" then return {} end
  return t
end

local host = ngx.var.host or ""
if host == "" then
  ngx.log(ngx.WARN, "No Host header; closing")
  return ngx.exit(444)
end

local map = read_json("/etc/nginx/domains.json")
local upstream = map[host]

if not upstream or upstream == "" then
  ngx.log(ngx.WARN, "No upstream mapping for host: " .. host)
  return ngx.exit(444)
end

-- set variabel Nginx $upstream
ngx.var.upstream = upstream
