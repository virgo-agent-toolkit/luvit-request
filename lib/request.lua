--[[
Copyright 2015 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]
local base64 = require('openssl').base64
local http = require('http')
local https = require('https')
local url = require('url')
local Error = require('core').Error

-- merge tables
local function merge(...)
  local args = {...}
  local first = args[1] or {}
  for i,t in pairs(args) do
    if i ~= 1 and t then
      for k, v in pairs(t) do
        first[k] = v
      end
    end
  end

  return first
end

local function proxy(uri, host, timeout, callback)
  local options = url.parse(uri)
  local proto = http

  if options.protocol == 'https' then
    proto = https
  end

  options.method = 'CONNECT'
  options.path = host
  options.headers = {
    { 'connection', 'keep-alive' }
  }

  if options.auth then
    local base64_auth = base64(options.auth)
    table.insert(options.headers, { 'Proxy-Authorization', 'Basic ' .. base64_auth } )
  end

  local req = proto.request(options)
  req:on('connect', function(response, socket, headers)
    if response.statusCode == 200 then
      socket:emit('alreadyConnected', socket)
      callback(nil, socket)
    else
      callback(Error:new('Proxy Error'))
    end
  end)
  req:setTimeout(timeout or 0, function()
    callback(Error:new('proxy timeout'))
  end)
  req:once('error', callback)
  req:done()
end

local function request(options, callback)
  local parsed = url.parse(options.url)
  local opts = merge({}, options, parsed)
  local proto = http
  local port = 80

  if parsed.protocol == 'https' then
    proto = https
    port = 443
  end

  if parsed.port then
    port = parsed.port
  end

  local function perform(proto, opts, callback)
    local client = proto.request(opts, function(res)
      callback(nil, res)
    end)
    client:once('error', callback)
    if opts.body then client:write(opts.body) end
    client:done()
  end

  if opts.proxy then
    proxy(opts.proxy, parsed.host .. ':' .. port, opts.timeout, function(err, socket)
      if err then return callback(err) end
      opts.socket = socket
      perform(proto, opts, callback)
    end)
  else
    perform(proto, opts, callback)
  end
end

exports.proxy = proxy
exports.request = request
