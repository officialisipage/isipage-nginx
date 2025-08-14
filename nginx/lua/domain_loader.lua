local cjson = require("cjson.safe")
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools

local function tbl_len(t) local c=0; for _ in pairs(t or {}) do c=c+1 end; return c end

local function load_domains()
  local f = io.open("/etc/nginx/domains.json", "r")
  if not f then
    ngx.log(ngx.WARN, "domains.json not found; creating empty")
    return
  end
  local content = f:read("*a"); f:close()
  local arr = cjson.decode(content) or {}
  local count = 0
  -- format baru: [{ "domain": "...", "pool": "pool_public" }, ...]
  for _, item in ipairs(arr) do
    if type(item) == "table" and item.domain and item.pool then
      dict_domains:set(item.domain, item.pool)
      count = count + 1
    end
  end
  ngx.log(ngx.INFO, "Loaded domains.json (" .. tostring(count) .. " entries)")
end

local function load_pools()
  local f = io.open("/etc/nginx/pools.json", "r")
  if not f then
    ngx.log(ngx.WARN, "pools.json not found; creating empty")
    return
  end
  local content = f:read("*a"); f:close()
  local pools = cjson.decode(content) or {}
  local pcount = 0
  for name, backends in pairs(pools) do
    if type(backends) == "table" then
      dict_pools:set("pool:" .. name, cjson.encode(backends))
      -- init counter jika belum ada
      dict_pools:add("rr:" .. name, 0)
      pcount = pcount + 1
    end
  end
  ngx.log(ngx.INFO, "Loaded pools.json (" .. tostring(pcount) .. " pools)")
end

local function load_file(path) local f=io.open(path,"r"); if not f then return nil end; local d=f:read("*a"); f:close(); return d end
local function set_domains(json)
  local arr = cjson.decode(json) or {}
  dict_domains:flush_all(); dict_domains:flush_expired()
  for _, it in ipairs(arr) do
    if it.domain and it.pool then dict_domains:set(it.domain, it.pool) end
  end
end
local function set_pools(json)
  local obj = cjson.decode(json) or {}
  for k,_ in pairs(obj) do dict_pools:delete("pool:"..k) end
  for name, backs in pairs(obj) do
    dict_pools:set("pool:"..name, cjson.encode(backs))
    dict_pools:add("rr:"..name, 0)
  end
end

local last_domains_hash, last_pools_hash

local function tick(premature)
  if premature then return end
  local domains = load_file("/etc/nginx/domains.json") or "[]"
  local pools   = load_file("/etc/nginx/pools.json")   or "{}"
  local dh, ph = ngx.md5(domains), ngx.md5(pools)
  if dh ~= last_domains_hash then set_domains(domains); last_domains_hash = dh end
  if ph ~= last_pools_hash   then set_pools(pools);     last_pools_hash   = ph end
end

-- pertama kali muat + jadwalkan cek setiap 5 detik
tick(false)
local ok, err = ngx.timer.every(5, tick)
if not ok then ngx.log(ngx.ERR, "timer.every failed: ", err) e

load_domains()
load_pools()
