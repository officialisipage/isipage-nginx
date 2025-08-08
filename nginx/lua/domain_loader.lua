local json = require("cjson")
local domains = ngx.shared.domains

local function load_domains()
    local file = io.open("/var/domains.json", "r")
    if not file then
        ngx.log(ngx.ERR, "⚠️  Cannot open domains.json")
        return
    end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(json.decode, content)
    if not ok then
        ngx.log(ngx.ERR, "❌ Failed to parse domains.json")
        return
    end

    for domain, target in pairs(data) do
        domains:set(domain, target)
    end

    ngx.log(ngx.INFO, "✅ Loaded domains from file")
end

load_domains()
