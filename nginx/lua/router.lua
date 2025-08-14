local cjson = require "cjson.safe"
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools

local host = ngx.var.host or ""
if host == "" then
  ngx.log(ngx.WARN, "No Host header")
  return ngx.exit(502)
end

local poolname = dict_domains:get(host)
if not poolname or poolname == "" then
  ngx.header["X-Debug-Reason"] = "domain_not_mapped"
  return ngx.exit(404)  -- atau 502 sesuai preferensi
end

-- Ambil daftar backend pool
local backends_json = dict_pools:get("pool:" .. poolname)
if not backends_json then
  ngx.log(ngx.ERR, "Pool '" .. poolname .. "' not found for host: " .. host)
  ngx.header["X-Debug-Reason"] = "pool_not_found"
  return ngx.exit(502)
end

local backends = cjson.decode(backends_json) or {}
if #backends == 0 then
  ngx.log(ngx.ERR, "Pool '" .. poolname .. "' empty for host: " .. host)
  ngx.header["X-Debug-Reason"] = "pool_empty"
  return ngx.exit(502)
end

-- Round-robin per pool
local ckey = "rr:" .. poolname
local n = #backends
local idx = dict_pools:incr(ckey, 1, 0)
local pick = backends[((idx - 1) % n) + 1]

local upstream = (pick.host or "127.0.0.1") .. ":" .. tostring(pick.port or 80)
ngx.var.upstream = upstream

-- Header debug biar gampang trace
ngx.header["X-Upstream"] = upstream
ngx.header["X-Pool"] = poolname
