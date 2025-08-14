-- lua/router.lua
local domain_loader = require "domain_loader"

-- dipanggil di access_by_lua*
return function()
  local host = ngx.var.host
  local pool = domain_loader.get_pool_for_host(host)
  ngx.ctx.selected_pool = pool
end
