local json = require("cjson")
local domains = ngx.shared.domains
local host = ngx.var.host

-- Coba ambil dari shared dict
local target = domains:get(host)

-- Jika tidak ditemukan, fallback baca dari file
if not target then
    local file = io.open("/var/domains.json", "r")
    if file then
        local content = file:read("*a")
        file:close()

        local ok, data = pcall(json.decode, content)
        if ok and data[host] then
            target = data[host]
            domains:set(host, target)  -- cache kembali
        end
    end
end

-- Jika masih tidak ada → 404
if not target then
    ngx.status = 404
    ngx.say("Domain not registered: ", host)
    ngx.exit(ngx.HTTP_NOT_FOUND)
end

-- Sukses → set upstream
ngx.var.upstream = target
