local dict = ngx.shared.domain_backends
return setmetatable({}, {
  __index = function(_, host)
    return dict:get(host)
  end
})
