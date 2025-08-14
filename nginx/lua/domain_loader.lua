local cjson = require("cjson.safe")
local dict_domains = ngx.shared.domains
local dict_pools   = ngx.shared.pools

local function load_domains()
  local f = io.open("/etc/nginx/domains.json", "r")
  if not f then
    ngx.log(ngx.WARN, "domains.json not found")
    return
  end
  local content = f:read("*a"); f:close()
  local arr = cjson.decode(content)
  if type(arr) ~= "table" then
    ngx.log(ngx.ERR, "domains.json not an array")
    return
  end
  local n = 0
  for _, item in ipairs(arr) do
    if type(item) == "table" and item.domain and item.pool then
      dict_domains:set(item.domain, item.pool)
      n = n + 1
    end
  end
  ngx.log(ngx.INFO, "Loaded domains.json (" .. tostring(n) .. " entries)")
end

local function load_pools()
  local f = io.open("/etc/nginx/pools.json", "r")
  if not f then
    ngx.log(ngx.WARN, "pools.json not found")
    return
  end
  local content = f:read("*a"); f:close()
  local pools = cjson.decode(content)
  if type(pools) ~= "table" then
    ngx.log(ngx.ERR, "pools.json invalid")
    return
  end
  local pcount = 0
  for name, backends in pairs(pools) do
    if type(backends) == "table" then
      dict_pools:set("pool:" .. name, cjson.encode(backends))
      dict_pools:add("rr:" .. name, 0)
      pcount = pcount + 1
    end
  end
  ngx.log(ngx.INFO, "Loaded pools.json (" .. tostring(pcount) .. " pools)")
end

load_domains()
load_pools()
