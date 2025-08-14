local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools
local json         = require "cjson.safe"

-- host yang diminta
local host = ngx.var.host or ""
if host == "" then
  ngx.header["X-Debug-Reason"] = "empty_host"
  return ngx.exit(400)
end

-- STRICT: hanya host penuh, tanpa turunan/akar/suffix match
local poolname = dict_domains:get(host)

-- TIDAK ADA FALLBACK KE pool_public!!
if not poolname or poolname == "" then
  ngx.header["X-Debug-Reason"] = "domain_not_mapped"
  return ngx.exit(404) -- atau 502 kalau mau
end

-- Ambil backends pool
local backends_json = dict_pools:get("pool:" .. poolname)
if not backends_json then
  ngx.header["X-Debug-Reason"] = "pool_not_found:" .. poolname
  return ngx.exit(502)
end

local backends = json.decode(backends_json) or {}
if type(backends) ~= "table" or #backends == 0 then
  ngx.header["X-Debug-Reason"] = "pool_empty:" .. poolname
  return ngx.exit(502)
end

-- Round-robin sederhana
local rrkey = "rr:" .. poolname
local idx   = dict_pools:incr(rrkey, 1, 0)
local n     = #backends
local pick  = backends[((idx - 1) % n) + 1]

ngx.var.upstream = (pick.host or "127.0.0.1") .. ":" .. tostring(pick.port or 80)
