-- /etc/nginx/lua/router.lua
local cjson = require "cjson.safe"
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools

local host = ngx.var.host or ""
if host == "" then
  ngx.log(ngx.WARN, "No Host header; closing")
  return ngx.exit(444)
end

-- cari pool untuk host
local poolname = dict_domains:get(host)
if not poolname or poolname == "" then
  ngx.log(ngx.WARN, "No pool mapping for host: " .. host)
  return ngx.exit(444)
end

-- ambil daftar backend pool
local backends_json = dict_pools:get("pool:" .. poolname)
if not backends_json then
  ngx.log(ngx.ERR, "Pool '" .. poolname .. "' not found for host: " .. host)
  return ngx.exit(502)
end

local backends = cjson.decode(backends_json) or {}
if #backends == 0 then
  ngx.log(ngx.ERR, "Pool '" .. poolname .. "' empty for host: " .. host)
  return ngx.exit(502)
end

-- Round-robin per pool (counter di shared dict)
local ckey = "rr:" .. poolname
local n = #backends
local idx = dict_pools:incr(ckey, 1, 0)
local pick = backends[( (idx - 1) % n ) + 1]

-- set variabel Nginx $upstream
ngx.var.upstream = (pick.host or "127.0.0.1") .. ":" .. tostring(pick.port or 80)
