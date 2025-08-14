local cjson        = require "cjson.safe"
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools
local conn_dict    = ngx.shared.conn_shdict    -- counter koneksi aktif
local health_dict  = ngx.shared.health_shdict  -- status down pasif: key "down:<pool>:ip:port" -> 1 (TTL)

-- host wajib ada
local host = ngx.var.host or ""
if host == "" then
  ngx.header["X-Debug-Reason"] = "empty_host"
  return ngx.exit(400)
end

-- STRICT: wajib terdaftar
local poolname = dict_domains:get(host)
if not poolname or poolname == "" then
  ngx.header["X-Debug-Reason"] = "domain_not_mapped"
  return ngx.exit(404)
end

-- ambil daftar backend untuk pool
local backends_json = dict_pools:get("pool:" .. poolname)
if not backends_json then
  ngx.header["X-Debug-Reason"] = "pool_not_found:" .. tostring(poolname)
  return ngx.exit(502)
end
local backends = cjson.decode(backends_json) or {}
if type(backends) ~= "table" or #backends == 0 then
  ngx.header["X-Debug-Reason"] = "pool_empty:" .. tostring(poolname)
  return ngx.exit(502)
end

-- kandidat sehat (skip yg ditandai down oleh health pasif)
local healthy = {}
for _, s in ipairs(backends) do
  local addr = (s.host or "127.0.0.1") .. ":" .. tostring(s.port or 80)
  local down = health_dict:get("down:" .. poolname .. ":" .. addr)
  if not down then
    table.insert(healthy, s)
  end
end
if #healthy == 0 then
  -- semua down -> pakai list asli agar tetap ada respons (retry tetap bisa terjadi)
  healthy = backends
end

-- deteksi retry & upstream yang harus dihindari
local hdrs     = ngx.req.get_headers()
local is_retry = (hdrs["X-Retry"] == "1")
local avoid    = hdrs["X-Prev-Upstream"] or (ngx.var.prev_up or "")

-- helper ambil (nconn, addr) utk server
local function nconn_of(s)
  local addr = (s.host or "127.0.0.1") .. ":" .. tostring(s.port or 80)
  local n = conn_dict:get("conn:" .. addr) or 0
  return n, addr
end

-- RR index per pool utk tie-break saat nconn sama
local rrkey = "lcrr:" .. poolname
local rridx = dict_pools:incr(rrkey, 1, 0)

-- LEAST-CONNECTIONS + RR tie-break, hindari 'avoid' saat retry
local function pick_least_conn_rr()
  local best = {}
  local best_n = nil

  for _, s in ipairs(healthy) do
    local n, addr = nconn_of(s)
    if not (is_retry and avoid ~= "" and addr == avoid) then
      if (best_n == nil) or (n < best_n) then
        best   = { { s = s, addr = addr } }
        best_n = n
      elseif n == best_n then
        table.insert(best, { s = s, addr = addr })
      end
    end
  end

  if #best == 0 then
    for _, s in ipairs(healthy) do
      local n, addr = nconn_of(s)
      if (best_n == nil) or (n < best_n) then
        best   = { { s = s, addr = addr } }
        best_n = n
      elseif n == best_n then
        table.insert(best, { s = s, addr = addr })
      end
    end
  end

  local j = ((rridx - 1) % #best) + 1
  return best[j].s, best[j].addr
end

local pick, addr = pick_least_conn_rr()
if not pick or not addr then
  ngx.header["X-Debug-Reason"] = "no_candidate"
  return ngx.exit(502)
end

-- set var untuk proxy_pass dan header debug
ngx.var.upstream = addr
ngx.var.pool     = poolname

-- inc active connections (dec dilakukan di log_by_lua di nginx.conf)
conn_dict:incr("conn:" .. addr, 1, 0)

-- set prev_up hanya pada request pertama (biar @retry bisa tahu)
if not is_retry then
  ngx.var.prev_up = addr
end

-- header debug
ngx.header["X-Upstream"] = addr
ngx.header["X-Pool"]     = poolname
