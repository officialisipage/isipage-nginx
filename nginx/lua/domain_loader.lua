-- lua/domain_loader.lua
local cjson = require "cjson.safe"
local _M = {}
local domains_shdict = ngx.shared.domains_shdict

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("*a"); f:close()
  return s
end

function _M.load_domains(json_path)
  local s, err = read_file(json_path)
  if not s then
    ngx.log(ngx.ERR, "load_domains error: ", err)
    return nil, err
  end
  domains_shdict:set("domains_json", s)
  return true
end

function _M.get_pool_for_host(host)
  if not host or host == "" then return "default" end
  local s = domains_shdict:get("domains_json")
  if not s then return "default" end
  local arr = cjson.decode(s)
  if type(arr) ~= "table" then return "default" end

  -- exact match
  for _, row in ipairs(arr) do
    if row.domain == host then
      return row.pool or "default"
    end
  end

  -- fallback: root-domain match (subdomain → base)
  local base = host:match("[^.]+%.([^.]+%.[^.]+)$")  -- ambil dua level terakhir
  if base then
    for _, row in ipairs(arr) do
      if row.domain == base then
        return row.pool or "default"
      end
    end
  end
  return "default"
end

return _M
