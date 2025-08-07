-- router.lua
local ngx = ngx
local uri = ngx.var.request_uri

-- Contoh routing dinamis sederhana
if uri:find("^/api/") then
    ngx.var.upstream = "127.0.0.1:3000"
elseif uri:find("^/admin/") then
    ngx.var.upstream = "127.0.0.1:8080"
else
    ngx.var.upstream = "127.0.0.1:5000"
end
