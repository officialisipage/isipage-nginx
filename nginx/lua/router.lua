local domains = ngx.shared.domains
local host = ngx.var.host

-- Cek domain di shared memory
local target = domains:get(host)

if target then
    ngx.var.upstream = target
else
    -- fallback ke default backend atau tolak
    ngx.status = 404
    ngx.say("Domain not registered")
    ngx.exit(ngx.HTTP_NOT_FOUND)
end
