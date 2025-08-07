local cjson = require "cjson"
local domains = ngx.shared.domains

-- ✅ Ambil query string secara aman
local args = ngx.req.get_uri_args()
local domain = args["domain"]
local target = args["target"] or "103.250.11.31:2000"

if not domain then
  ngx.status = 400
  ngx.say("Missing domain parameter")
  return
end

-- ✅ Simpan ke shared memory
domains:set(domain, target)

-- ✅ Baca domains.json yang ada
local filepath = "/etc/nginx/domains.json"
local file = io.open(filepath, "r")
local content = file and file:read("*a") or "{}"
if file then file:close() end

local ok, data = pcall(cjson.decode, content)
if not ok then data = {} end

-- ✅ Tambahkan / update domain
data[domain] = target

-- ✅ Tulis ulang file
file = io.open(filepath, "w+")
file:write(cjson.encode(data))
file:close()

ngx.status = 200
ngx.say("✅ Domain saved: ", domain, " → ", target)
