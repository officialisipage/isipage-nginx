-- lua/pools.lua
local cjson = require "cjson.safe"
local healthcheck = require "resty.upstream.healthcheck"  -- jika pakai lib ini
local _M = {}

local pools_shdict = ngx.shared.pools_shdict
local health_shdict = ngx.shared.health_shdict

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("*a"); f:close()
  return s
end

function _M.load_pools(json_path)
  local s, err = read_file(json_path)
  if not s then
    ngx.log(ngx.ERR, "load_pools error: ", err)
    return nil, err
  end
  local obj, perr = cjson.decode(s)
  if not obj then
    ngx.log(ngx.ERR, "invalid pools.json: ", perr)
    return nil, perr
  end
  -- simpan ke shared dict
  pools_shdict:set("pools_json", s)
  return true
end

function _M.get_pool(name)
  local s = pools_shdict:get("pools_json")
  if not s then return nil, "pools not loaded" end
  local obj = cjson.decode(s)
  return obj[name] or obj["default"]
end

-- optional: health check background (gunakan lua-resty-upstream-healthcheck)
function _M.start_health_checks()
  -- Pseudo: jika tak mau pakai lib, skip.
  -- Dengan lib ini kamu perlu definisikan upstream Nginx; kalau full dynamic, bisa bikin checker custom (HEAD /health)
  return true
end

return _M
