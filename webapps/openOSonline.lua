local internet = component.proxy(component.list("internet")())
local computer_pullSignal = computer.pullSignal
local computer_pushSignal = computer.pushSignal
local computer, component, unicode = computer, component, unicode

local _, depth = pcall(component.invoke, computer.getBootGpu(), "getDepth")
pcall(component.invoke, computer.getBootGpu(), "setDepth", 1)
pcall(component.invoke, computer.getBootGpu(), "setDepth", depth)

local proxylist = {}
local proxyobjs = {}
local typelist = {}
local doclist = {}

local oproxy = component.proxy
function component.proxy(address)
  checkArg(1,address,"string")
  if proxyobjs[address] ~= nil then
    return proxyobjs[address]
  end
  return oproxy(address)
end

local olist = component.list
function component.list(filter, exact)
  checkArg(1,filter,"string","nil")
  local result = {}
  local data = {}
  for k,v in olist(filter, exact) do
    data[#data + 1] = k
    data[#data + 1] = v
    result[k] = v
  end
  for k,v in pairs(typelist) do
    if filter == nil or (exact and v == filter) or (not exact and v:find(filter, nil, true)) then
      data[#data + 1] = k
      data[#data + 1] = v
      result[k] = v
    end
  end
  local place = 1
  return setmetatable(result, 
    {__call=function()
      local addr,type = data[place], data[place + 1]
      place = place + 2
      return addr, type
    end}
  )
end

local otype = component.type
function component.type(address)
  checkArg(1,address,"string")
  if typelist[address] ~= nil then
    return typelist[address]
  end
  return otype(address)
end

local odoc = component.doc
function component.doc(address, method)
  checkArg(1,address,"string")
  checkArg(2,method,"string")
  if proxylist[address] ~= nil then
    if proxylist[address][method] == nil then
      error("no such method",2)
    end
    if doclist[address] ~= nil then
      return doclist[address][method]
    end
    return nil
  end
  return odoc(address, method)
end

local oslot = component.slot
function component.slot(address)
  checkArg(1,address,"string")
  if proxylist[address] ~= nil then
    return -1 -- vcomponents do not exist in a slot
  end
  return oslot(address)
end

local omethods = component.methods
function component.methods(address)
  checkArg(1,address,"string")
  if proxylist[address] ~= nil then
    local methods = {}
    for k,v in pairs(proxylist[address]) do
      if type(v) == "function" then
        methods[k] = true -- All vcomponent methods are direct
      end
    end
    return methods
  end
  return omethods(address)
end

local oinvoke = component.invoke
function component.invoke(address, method, ...)
  checkArg(1,address,"string")
  checkArg(2,method,"string")
  if proxylist[address] ~= nil then
    if proxylist[address][method] == nil then
      error("no such method",2)
    end
    return proxylist[address][method](...)
  end
  return oinvoke(address, method, ...)
end

local ofields = component.fields
function component.fields(address)
  checkArg(1,address,"string")
  if proxylist[address] ~= nil then
    return {} -- What even is this?
  end
  return ofields(address)
end

local componentCallback =
{
  __call = function(self, ...) return proxylist[self.address][self.name](...) end,
  __tostring = function(self) return (doclist[self.address] ~= nil and doclist[self.address][self.name] ~= nil) and doclist[self.address][self.name] or "function" end
}

local vcomponent = {}

function vcomponent.register(address, ctype, proxy, doc)
  checkArg(1,address,"string")
  checkArg(2,ctype,"string")
  checkArg(3,proxy,"table")
  if proxylist[address] ~= nil then
    return nil, "component already at address"
  elseif component.type(address) ~= nil then
    return nil, "cannot register over real component"
  end
  proxy.address = address
  proxy.type = ctype
  local proxyobj = {}
  for k,v in pairs(proxy) do
    if type(v) == "function" then
      proxyobj[k] = setmetatable({name=k,address=address},componentCallback)
    else
      proxyobj[k] = v
    end
  end
  proxylist[address] = proxy
  proxyobjs[address] = proxyobj
  typelist[address] = ctype
  doclist[address] = doc
  computer_pushSignal("component_added",address,ctype)
  return true
end

function vcomponent.unregister(address)
  checkArg(1,address,"string")
  if proxylist[address] == nil then
    if component.type(address) ~= nil then
      return nil, "cannot unregister real component"
    else
      return nil, "no component at address"
    end
  end
  local thetype = typelist[address]
  proxylist[address] = nil
  proxyobjs[address] = nil
  typelist[address] = nil
  doclist[address] = nil
  computer_pushSignal("component_removed",address,thetype)
  return true
end

function vcomponent.list()
  local list = {}
  for k,v in pairs(proxylist) do
    list[#list + 1] = {k,typelist[k],v}
  end
  return list
end

function vcomponent.resolve(address, componentType)
  checkArg(1, address, "string")
  checkArg(2, componentType, "string", "nil")
  for k,v in pairs(typelist) do
    if componentType == nil or v == componentType then
      if k:sub(1, #address) == address then
        return k
      end
    end
  end
  return nil, "no such component"
end

local r = math.random
function vcomponent.uuid()
  return string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
  r(0,255),r(0,255),r(0,255),r(0,255),
  r(0,255),r(0,255),
  r(64,79),r(0,255),
  r(128,191),r(0,255),
  r(0,255),r(0,255),r(0,255),r(0,255),r(0,255),r(0,255))
end

------------------------------------

local url = "https://raw.githubusercontent.com/igorkll/openOS/main"

local function getInternetFile(url)--взято из mineOS efi от игорь тимофеев
    local handle, data, result, reason = internet.request(url), ""
    if handle then
        while 1 do
            result, reason = handle.read(math.huge)
            if result then
                data = data .. result
            else
                handle.close()
                
                if reason then
                    return a, reason
                else
                    return data
                end
            end
        end
    else
        return a, "Unvalid Address"
    end
end

local function split(str, sep)
    local parts, count, i = {}, 1, 1
    while 1 do
        if i > #str then break end
        local char = str:sub(i, #sep + (i - 1))
        if not parts[count] then parts[count] = "" end
        if char == sep then
            count = count + 1
            i = i + #sep
        else
            parts[count] = parts[count] .. str:sub(i, i)
            i = i + 1
        end
    end
    if str:sub(#str - (#sep - 1), #str) == sep then table.insert(parts, "") end
    return parts
end

local function segments(path)
    local parts = {}
    for part in path:gmatch("[^\\/]+") do
        local current, up = part:find("^%.?%.$")
        if current then
            if up == 2 then
                table.remove(parts)
            end
        else
            table.insert(parts, part)
        end
    end
    return parts
end
  
local function fs_path(path)
    local parts = segments(path)
    local result = table.concat(parts, "/", 1, #parts - 1) .. "/"
    if unicode.sub(path, 1, 1) == "/" and unicode.sub(result, 1, 1) ~= "/" then
        return "/" .. result
    else
        return result
    end
end

local function fs_name(path)
    checkArg(1, path, "string")
    local parts = segments(path)
    return parts[#parts]
end

if status then
    status("Downloading Filelist")
end
local files = split(assert(getInternetFile(url .. "/filelist.txt")), "\n")
local directorys = {}

local function inTable(tbl, data)
    for k, v in pairs(tbl) do
        if v == data then
            return true
        end
    end
end

local oldinterrupttime = computer.uptime()
local function interrupt()
    if computer.uptime() - oldinterrupttime > 3 then
        oldinterrupttime = computer.uptime()
        local eve = {computer_pullSignal(0.1)}
        if #eve ~= 0 then
            computer_pushSignal(table.unpack(eve))
        end
    end
end

for i, v in ipairs(files) do
    local path = v
    while true do
        path = fs_path(path)
        if not inTable(directorys, path) then
            table.insert(directorys, path)
        end
        if path == "/" or path == "" then
            break
        end
        interrupt()
    end
    interrupt()
end

local function createFileStream(path, mode)
    if not mode then mode = "rb" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    local stringControl
    if mode == "rb" then
        stringControl = string
    elseif mode == "r" then
        stringControl = unicode
    elseif mode == "wb" or mode == "w" then
        return nil, "filesystem is readonly"
    else
        error("unsupported mode", 0)
    end

    local fileurl = url .. path

    local obj = {}

    obj.position = 0
    obj.data = getInternetFile(fileurl)
    if not obj.data then
        return nil, "file not found"
    end
    obj.closed = false
    obj.stringControl = stringControl
    obj.size = stringControl.len(obj.data)

    return obj
end

------------------------------------

local fs = {}

fs.open = createFileStream

function fs.remove()
    interrupt()
    return nil, "filesystem is readonly"
end

function fs.rename()
    interrupt()
    return nil, "filesystem is readonly"
end

function fs.isReadOnly()
    interrupt()
    return true
end

function fs.spaceUsed()
    interrupt()
    return math.huge
end

function fs.spaceTotal()
    interrupt()
    return math.huge
end

function fs.isDirectory(path)
    interrupt()
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    if path:sub(#path, #path) ~= "/" then path = path .. "/" end
    return inTable(directorys, path)
end

function fs.exists(path)
    interrupt()
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    if path:sub(#path, #path) == "/" then path = path:sub(1, #path - 1) end
    local ok1 = inTable(files, path)
    if ok1 then return true end
    if path:sub(#path, #path) ~= "/" then path = path .. "/" end
    local ok2 = inTable(directorys, path)
    return ok2
end

function fs.list(path)
    interrupt()
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    if path:sub(#path, #path) ~= "/" then path = path .. "/" end

    local list = {}

    for i, v in ipairs(files) do
        if fs_path(v) == path then
            table.insert(list, fs_name(v))
        end
    end
    for i, v in ipairs(directorys) do
        if fs_path(v) == path then
            local value = fs_name(v)
            if value then
                table.insert(list, value .. "/")
            end
        end
    end

    list.n = #list
    return list
end

function fs.lastModified(path)
    interrupt()
    return -math.huge
end

function fs.getLabel()
    interrupt()
    return "openOSonline"
end

function fs.setLabel()
    interrupt()
    error("label is readonly")
end

function fs.size(path)
    if not fs.exists(path) then return nil, "file not found" end
    if fs.isDirectory(path) then return nil, "is directory" end
    interrupt()
    return #createFileStream(path, "rb").data
end

function fs.close(file)
    interrupt()
    local old = file.closed
    file.closed = true
    return not old
end

function fs.read(file, bytes)
    interrupt()
    bytes = math.floor(bytes)
    if file.closed then return nil, "file closed" end
    
    local startNumber = file.position
    local endNumber = (file.position + bytes) - 1
    if endNumber == math.huge then
        endNumber = file.size
    end

    local data = file.stringControl.sub(file.data, startNumber + 1, endNumber + 1)
    file.position = file.position + bytes
    if file.position > file.size then
        file.position = file.size
    end

    if data == "" then data = nil end
    return data
end

function fs.write(file)
    interrupt()
    return nil, "filesystem is readonly"
end

function fs.seek(file, mode, bytes)
    interrupt()
    bytes = math.floor(bytes)
    if file.closed then return nil, "file closed" end
    if file == "set" then
        file.position = bytes
    elseif file == "cur" then
        file.position = file.position + bytes
        if file.position < 0 then
            file.position = 0
        end
        if file.position > file.size then
            file.position = mayh.floor(file.size)
        end
    else
        error("unsupported mode", 0)
    end
    return file.position
end

local address = vcomponent.uuid()

computer.getBootAddress = function()
    return address
end

computer.getBootFile = function()
    return "/init.lua"
end

vcomponent.register(address, "filesystem", fs, {})

local file = fs.open("/init.lua", "rb")
local data = fs.read(file, math.huge)
fs.close(file)

if status then status("booting") end
local ok, err = pcall(assert(load(data, '=init')))
if not ok then
    if status then
        status(err or "unknown error")
        while true do
            computer_pullSignal()
        end
    end
end
computer.shutdown()