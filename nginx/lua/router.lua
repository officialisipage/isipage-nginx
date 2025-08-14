local cjson        = require "cjson.safe"
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools
local conn_dict    = ngx.shared.conn_shdict    -- counter koneksi aktif
local health_dict  = ngx.shared.health_shdict  -- status down pasif

-- host wajib ada
local host = ngx.var.host or ""
if host == "" then
  ngx.header["X-Debug-Reason"] = "empty_host"
  return ngx.exit(400)
end

-- STRICT: wajib terdaftar di domains.json
local poolname = dict_domains:get(host)
if not poolname or poolname == "" then
  ngx.header["X-Debug-Reason"] = "domain_not_mapped"
  return ngx.exit(404)
end

-- Ambil daftar backend untuk pool tsb
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

-- Bangun kandidat sehat (skip yg sedang down pasif)
local healthy = {}
for _, s in ipairs(backends) do
  local addr = (s.host or "127.0.0.1") .. ":" .. tostring(s.port or 80)
  local down = health_dict:get("down:" .. poolname .. ":" .. addr)
  if not down then
    table.insert(healthy, s)
  end
end
if #healthy == 0 then
  -- jika semua down → tetap gunakan list asli agar tetap ada respons
  healthy = backends
end

-- Apakah ini retry? (datang dari named location @retry di nginx.conf)
local hdrs     = ngx.req.get_headers()
local is_retry = (hdrs["X-Retry"] == "1")
local avoid    = hdrs["X-Prev-Upstream"] or (ngx.var.prev_up or "")

-- Fungsi: ambil counter koneksi aktif per addr
local function nconn_of(s)
  local addr = (s.host or "127.0.0.1") .. ":" .. tostring(s.port or 80)
  local n = conn_dict:get("conn:" .. addr) or 0
  return n, addr
end

-- Algoritma: LEAST-CONNECTIONS di antara kandidat "healthy"
-- Hindari 'avoid' jika ini retry, selama masih ada kandidat lain.
local function pick_least_conn()
  local best_s, best_addr, best_n
  for _, s in ipairs(healthy) do
    local n, addr = nconn_of(s)
    if not (is_retry and avoid ~= "" and addr == avoid) then
      if (not best_n) or n < best_n then
        best_s, best_addr, best_n = s, addr, n
      end
    end
  end
  if not best_s then
    -- semua kandidat sama dengan 'avoid' → pilih paling kecil tanpa filter
    for _, s in ipairs(healthy) do
      local n, addr = nconn_of(s)
      if (not best_n) or n < best_n then
        best_s, best_addr, best_n = s, addr, n
      end
    end
  end
  return best_s, best_addr
end

local pick, addr = pick_least_conn()
if not pick or not addr then
  ngx.header["X-Debug-Reason"] = "no_candidate"
  return ngx.exit(502)
end

-- Set var untuk dipakai proxy_pass dan header debug
ngx.var.upstream = addr
ngx.var.pool     = poolname

-- Increment active connections untuk node terpilih (dec dilakukan di log_by_lua)
conn_dict:incr("conn:" .. addr, 1, 0)

-- Jangan timpa $prev_up saat retry; biarkan berisi upstream pertama
if not is_retry then
  ngx.var.prev_up = addr
end

-- Header debug (optional)
ngx.header["X-Upstream"] = addr
ngx.header["X-Pool"]     = poolname
