local cjson = require "cjson.safe"
local domains_dict = ngx.shared.domains
local pools_dict   = ngx.shared.pools

-- (Penting) Hapus isi lama supaya wildcard/akar yg dulu tersisa tidak kepakai
domains_dict:flush_all()
pools_dict:flush_all()

-- Load pools.json
do
  local f = io.open("/etc/nginx/pools.json", "r")
  if f then
    local s = f:read("*a"); f:close()
    local pools = cjson.decode(s) or {}
    for name, backends in pairs(pools) do
      pools_dict:set("pool:" .. name, cjson.encode(backends))
    end
  end
end

-- Load domains.json (harus array of { "domain": "...", "pool": "..." })
do
  local f = io.open("/etc/nginx/domains.json", "r")
  if f then
    local s = f:read("*a"); f:close()
    local arr = cjson.decode(s) or {}
    for _, item in ipairs(arr) do
      if item.domain and item.pool then
        -- STRICT: simpan apa adanya (FQDN), jangan diubah ke apex/suffix
        domains_dict:set(item.domain, item.pool)
      end
    end
  end
end
