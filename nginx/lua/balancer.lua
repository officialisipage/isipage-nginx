-- lua/balancer.lua
local balancer = require "ngx.balancer"
local cjson = require "cjson.safe"

local pools = require "pools"  -- lua/pools.lua
local conn_shdict = ngx.shared.conn_shdict

local _M = {}

-- ambil counter koneksi per node key "host:port"
local function get_conn(host, port)
  local key = host .. ":" .. tostring(port)
  return conn_shdict:get(key) or 0
end

-- increment/decrement via log_by_lua
function _M.inc_conn(host, port)
  conn_shdict:incr(host .. ":" .. port, 1, 0)
end
function _M.dec_conn(host, port)
  conn_shdict:incr(host .. ":" .. port, -1, 0)
end

-- pilih node dengan koneksi paling kecil (bisa tambahkan filter health)
local function pick_least_conn(servers)
  local best, best_i
  for i, s in ipairs(servers) do
    local n = get_conn(s.host, s.port)
    if (not best) or n < best then
      best = n; best_i = i
    end
  end
  return servers[best_i]
end

function _M.balance()
  local pool_name = ngx.ctx.selected_pool or "default"
  local servers = pools.get_pool(pool_name)
  if not servers or #servers == 0 then
    return ngx.exit(502)
  end

  local node = pick_least_conn(servers)
  if not node then
    return ngx.exit(502)
  end

  -- set peer
  local ok, err = balancer.set_current_peer(node.host, node.port)
  if not ok then
    ngx.log(ngx.ERR, "balancer set_current_peer fail: ", err)
    return ngx.exit(502)
  end

  -- simpan node yang dipakai ke ctx untuk dec di log phase
  ngx.ctx.lb_host = node.host
  ngx.ctx.lb_port = node.port

  -- increment sekarang (agar efek terlihat), nanti dec di log phase
  _M.inc_conn(node.host, node.port)
end

return _M
