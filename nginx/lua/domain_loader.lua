local cjson = require("cjson.safe")
local dict = ngx.shared.domains

local function tbl_len(t) local c=0; for _ in pairs(t or {}) do c=c+1 end; return c end

local function load_domains()
  local f = io.open("/etc/nginx/domains.json", "r")
  if not f then
    ngx.log(ngx.ERR, "Cannot open /etc/nginx/domains.json")
    return
  end
  local content = f:read("*a"); f:close()
  local data = cjson.decode(content) or {}
  for k, v in pairs(data) do dict:set(k, v) end
  ngx.log(ngx.INFO, "Loaded domains.json (" .. tbl_len(data) .. " entries)")
end

load_domains()
