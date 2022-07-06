--[[
--планируемые фичи
загрузка в MineOS
загрузка в разнае файлы /boot/kernel
защита по паролю

--данные в eeprom data
1.загрузочьной адрес
2.адрес монитора
3.загрузочный файл
4.hesh пароля
5.режим работы пароля
6.reboot mode
]]

biosname = "microBios"
statusAllow = 1
local init
do
    local p, c = computer, component
    local type, True, deviceinfo, depth, rx, ry, paletteSupported = type, true, p.getDeviceInfo() --type ипользуеться после загрузчи

    ------------------------------------------core

    local function hesh(str)
        local rv1, rv2, rv3, str2, anys = 126, 1671, 7124, "", {}

        for i = 1, #str do
            table.insert(anys, str:byte(i))
        end
    
        for i = 1, #str do
            local old, next, current = str:byte(i - 1), str:byte(i + 1), str:byte(i)
            if not old then old = str:byte(#str) end
            if not next then next = str:byte(1) end

            local v = (old * rv1) + (next * rv2) + (current * rv3)
            v = v + (i * rv2)
            v = v * (rv3 - (#str - i))
    
            for i2, v2 in ipairs(anys) do
                v = v + (v2 - (i * i2 * (rv1 - rv2)))
            end
    
            v = math.abs(v)
            v = v % 256
    
            str2 = str2 .. string.char(v)
            if #str2 == 16 then
                local char = str2:byte(1)
                rv1 = rv1 + char
                rv2 = rv2 * char
                rv3 = rv3 * char
                str2 = str2:sub(2, #str2)
            end
        end
    
        while #str2 < 16 do
            str2 = string.char(math.abs(rv3 + (rv2 * #str2)) % 256) .. str2
        end
    
        return str2
    end

    local function getCp(ctype)
        return c.proxy(c.list(ctype)() or "*")
    end
    local eeprom = getCp"eeprom"

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

    local function getDataPart(part)
        return split(eeprom.getData(), "\n")[part] or ""
    end

    local function setDataPart(part, newdata)
        if getDataPart(part) == newdata then return end
        if newdata:find"\n" then error"\\n char" end
        local parts = split(eeprom.getData(), "\n")
        for i = part, 1, -1 do
            if not parts[i] then parts[i] = "" end
        end
        parts[part] = newdata
        eeprom.setData(table.concat(parts, "\n"))
    end

    local function getBestGPUOrScreenAddress(componentType) --функцию подарил игорь тимофеев
        local bestAddress, bestWidth, width

        for address in c.list(componentType) do
            width = tonumber(deviceinfo[address].width)
            if c.type(componentType) == "screen" then
                if #c.invoke(address, "getKeyboards") > 0 then --экраны с кравиатурами имеют больший приоритет
                    width = width + 10
                end
            end

            if not bestWidth or width > bestWidth then
                bestAddress, bestWidth = address, width
            end
        end

        return bestAddress
    end

    local function delay(time, func)
        local inTime = p.uptime()
        while p.uptime() - inTime < time do
            func()
        end
    end

    ------------------------------------------init

    local internet, gpu, screen, keyboards = getCp"internet", c.proxy(getBestGPUOrScreenAddress"gpu" or ""), a, {}

    if gpu then
        screen = getDataPart(2)
        if c.type(screen) ~= "screen" then --если компонент не найден или это не монитор
            screen = getBestGPUOrScreenAddress"screen" --если компонента нет то screen будет nil автоматически
            if screen then setDataPart(2, screen) end --запомнить выбор
        end
        if screen then
            keyboards = c.invoke(screen, "getKeyboards")
            gpu.bind(screen)
        end
        pcall(gpu.setResolution, 80, 25) --что на экране t3 не было так пусто
    end

    ------------------------------------------functions

    local function tofunction(value)
        return function()
            return value
        end
    end

    p.getBootGpu = tofunction(gpu and gpu.address)
    p.getBootFile = function() return getDataPart(3) end
    p.getBootScreen = tofunction(screen)
    p.getBootAddress = function() return getDataPart(1) end
    
    function p.setBootFile(file) setDataPart(3, file) end
    function p.setBootScreen(screen) setDataPart(2, screen) end
    function p.setBootAddress(address) setDataPart(1, address) end

    local shutdown = p.shutdown
    function p.shutdown(reboot)
        if type(reboot) == "string" then
            setDataPart(6, reboot)
        end
        shutdown(reboot)
    end

    local function isValideKeyboard(address)
        for i, v in ipairs(keyboards) do
            if v == address then
                return 1
            end
        end
    end

    local function getLabel(address)
        local proxy = c.proxy(address)
        return proxy.getLabel() and (proxy.address:sub(1, 4) .. ":" .. proxy.getLabel()) or proxy.address:sub(1, 4)
    end

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

    ------------------------------------------graphic init

    local function resetpalette()
        paletteSupported = a
        if gpu.getDepth() > 1 then
            paletteSupported = True
            gpu.setDepth(1)
            gpu.setDepth(gpu.maxDepth())
        end
    end

    if screen then
        depth = math.floor(gpu.getDepth())
        rx, ry = gpu.getResolution()

        resetpalette()
        if paletteSupported then --индексация с 1 хотя начало у палитры с 0 потому что пре передаче light blue на первом мониторе всеравно должен быть белый
            gpu.setPaletteColor(1, 0x7B68EE) --light blue
            gpu.setPaletteColor(2, 0x1E90FF) --blue
            gpu.setPaletteColor(3, 0x6B8E23) --green
            gpu.setPaletteColor(4, 0x8B0000) --red
            gpu.setPaletteColor(5, 0xDAA520) --yellow
            gpu.setPaletteColor(6, 0) --black
            gpu.setPaletteColor(7, 0xFFFFFF) --white
            gpu.setPaletteColor(8, 0x00FF00) --lime
        end
    end

    ------------------------------------------gui

    local function setText(str, posX, posY)
        gpu.set((posX or 0) + math.floor(((rx / 2) - ((#str - 1) / 2)) + .5), posY or math.floor((ry / 2) + .5), str)
    end

    local function clear()
        gpu.setBackground(0)
        gpu.setForeground(0xFFFFFF)
        gpu.fill(1, 1, rx, ry, " ")
    end

    local function status(str, color, time, err, nonPalette)
        if not screen then
            if err then error(err, 0) end
            return
        end
        clear()
        gpu.setForeground(color or 1, not nonPalette and paletteSupported)
        setText(str)
        if err then
            p.beep(80, 0)
            p.beep(50, 0)
        end
        if time == True then
            setText("Press Enter To Continue", a, math.floor((ry / 2) + .5) + 1)
            while 1 do
                local eventData = {p.pullSignal()}
                if eventData[1] == "key_down" and isValideKeyboard(eventData[2]) and eventData[4] == 28 then
                    break
                end
            end
        elseif time then
            delay(time, function()
                p.pullSignal(0)
            end)
        end
        return 1
    end
    _G.status = function(str)--для лога загрузки openOSmod
        status(str, 0xFFFFFF, a, a, 1)
    end

    local function input(str, crypt, col)
        local buffer = ""
        
        local function redraw()
            status(str .. ": " .. (crypt and string.rep("*", #buffer) or buffer) .. "_", col or 5)
        end
        redraw()

        while 1 do
            local eventData = {p.pullSignal()}
            if isValideKeyboard(eventData[2]) then
                if eventData[1] == "key_down" then
                    if eventData[4] == 28 then
                        return buffer
                    elseif eventData[3] >= 32 and eventData[3] <= 126 then
                        buffer = buffer .. string.char(eventData[3])
                        redraw()
                    elseif eventData[4] == 14 then
                        if #buffer > 0 then
                            buffer = buffer:sub(1, #buffer - 1)
                            redraw()
                        end
                    elseif eventData[4] == 46 then
                        break --exit ctrl + c
                    end
                elseif eventData[1] == "clipboard" and not crypt then
                    buffer = buffer .. eventData[3]
                    redraw()
                    if buffer:byte(#buffer) == 13 then return buffer end
                end
            end
        end
    end

    local function createMenu(label, labelcolor, num)
        local obj, elements, selectedNum = {}, {}, num or 1

        function obj.a(...) --str, color, func
            table.insert(elements, {...})
        end

        local function draw()
            clear()
            gpu.setForeground(labelcolor, paletteSupported)
            setText(label, a, ry // 3)

            local old, current, next = elements[selectedNum - 1], elements[selectedNum], elements[selectedNum + 1]

            gpu.setBackground(0)
            if old then
                gpu.setForeground(old[2], paletteSupported)
                setText(old[1], -(rx // 3), (ry // 3) * 2)
            end
            if next then
                gpu.setForeground(next[2], paletteSupported)
                setText(next[1], rx // 3, (ry // 3) * 2)
            end

            gpu.setBackground(current[2], paletteSupported)
            gpu.setForeground(0)
            setText(current[1], a, (ry // 3) * 2)
        end

        function obj.l()
            draw()
            while 1 do
                local eventData = {p.pullSignal()}
                if eventData[1] == "key_down" and isValideKeyboard(eventData[2]) then
                    if eventData[4] == 28 then
                        if not elements[selectedNum][3] then break end
                        local ret = elements[selectedNum][3]()
                        if ret then return ret end
                        draw()
                    elseif eventData[4] == 205 then
                        if selectedNum < #elements then
                            selectedNum = selectedNum + 1
                            draw()
                        end
                    elseif eventData[4] == 203 then
                        if selectedNum > 1 then
                            selectedNum = selectedNum - 1
                            draw()
                        end
                    end
                end
            end
        end

        return obj
    end

    ------------------------------------------main

    local rebootMode = getDataPart(6)
    setDataPart(6, "")

    local function searchBootableFile(address)
        local proxy = c.proxy(address)
        if proxy.exists"/boot/kernel/pipes" then
            return "/boot/kernel/pipes"
        elseif screen then --если есть монитор то mineOS выше приоритетом
            if proxy.exists"/OS.lua" then
                return "/OS.lua"
            elseif proxy.exists"/init.lua" then
                return "/init.lua"
            end
        else
            if proxy.exists"/init.lua" then
                return "/init.lua"
            elseif proxy.exists"/OS.lua" then
                return "/OS.lua"
            end
        end
    end

    local function pleasWait()
        status("Please Wait", 5)
    end

    local function checkPassword()
        if getDataPart(4) == "" then return 1 end
        while 1 do
            local read = input("Enter Password", 1)
            if not read then break end
            if hesh(read) == getDataPart(4) then return 1 end
        end
    end

    local function biosMenu()
        if getDataPart(5) == "" and not checkPassword() then shutdown() end

        local mainmenu = createMenu("micro bios", 2)
        mainmenu.a("Back", 4)
        mainmenu.a("Reboot", 4, function() shutdown(1) end)
        mainmenu.a("Shutdown", 4, shutdown)

        if internet then
            mainmenu.a("Url Boot", 8, function()
                local url = input("Url", a, 8)
                if url then
                    status("Downloading Script", 8)
                    local data, err = getInternetFile(url)
                    if data then
                        local func, err = load(data, "=urlboot")
                        if func then
                            local ok, err = pcall(func)
                            if not ok then
                                status(err or "unknown error", 4, True, 1)
                            end
                        else
                            status(err, 4, True, 1)
                        end
                    else
                        status(err, 4, True, 1)
                    end
                end
            end)
        end

        mainmenu.a("Password", 5, function()
            if checkPassword() then
                local mainmenu = createMenu("Password", 3)

                mainmenu.a("Set Password", 5, function()
                    local p1 = input("Enter New Password", 1)
                    if p1 and p1 ~= "" and p1 == input("Confirm New Password", 1) then
                        pleasWait()
                        setDataPart(4, hesh(p1))
                    end
                end)

                mainmenu.a("Set Password Mode", 5, function()
                    local mainmenu = createMenu("Select Mode", 3)

                    mainmenu.a("Menu", 5, function()
                        pleasWait()
                        setDataPart(5, "")
                        return 1
                    end)

                    mainmenu.a("Boot", 5, function()
                        pleasWait()
                        setDataPart(5, "1")
                        return 1
                    end)

                    mainmenu.a("Disable", 5, function()
                        pleasWait()
                        setDataPart(5, "2")
                        return 1
                    end)

                    mainmenu.a("Back", 4)
                    mainmenu.l()
                end)

                mainmenu.a("Clear Password", 5, function()
                    pleasWait()
                    setDataPart(4, "")
                    setDataPart(5, "")
                end)

                mainmenu.a("Back", 4)
                mainmenu.l()
            end
        end)

        for address in c.list"filesystem" do
            local label = getLabel(address)
            mainmenu.a(label, 1, function()
                local mainmenu, proxy, files, path = createMenu("Drive " .. label, 2), c.proxy(address),
                {"/init.lua", "/OS.lua"}, "/boot/kernel/"

                for i = 2, 1, -1 do
                    if not proxy.exists(files[i]) then
                        table.remove(files, i)
                    end
                end

                for _, file in ipairs(proxy.list(path) or {}) do
                    table.insert(files, path .. file)
                end

                if #files > 0 then
                    mainmenu.a("boot", 1, function()
                        local file = searchBootableFile(address)
                        if file then
                            pleasWait()
                            setDataPart(1, address)
                            setDataPart(3, file)
                            return 1
                        end
                        status("Boot File Is Not Found", a, True, 1)
                    end)
                end

                local function addFile(file)
                    if c.invoke(address, "exists", file) then
                        local tbl = split(file, "/")
                        mainmenu.a(tbl[#tbl], 1, function()
                            pleasWait()
                            setDataPart(1, address)
                            setDataPart(3, file)
                            return 1
                        end)
                    end
                end
                for i, v in ipairs(files) do
                    addFile(v)
                end

                mainmenu.a("Back", 4)
                return mainmenu.l()
            end)
        end
        
        mainmenu.l()
    end

    p.beep(1500, 0.2)

    if rebootMode ~= "fast" and getDataPart(5) == "1" and (not screen or not checkPassword()) then --при fast reboot не будет спрашиваться пароль
        shutdown()
    end

    if screen then
        if rebootMode == "bios" then
            biosMenu()
        elseif rebootMode ~= "fast" and #keyboards > 0 and status"Press Alt To Open The Bios Menu" then
            delay(1, function()
                local eventData = {p.pullSignal(.1)}
                if eventData[1] == "key_down" and isValideKeyboard(eventData[2]) and eventData[4] == 56 then
                    biosMenu()
                end
            end)
        end
    end

    local bootaddress, file = getDataPart(1), getDataPart(3)
    local bootfs = c.proxy(bootaddress)

    if not bootfs or not bootfs.exists(file) then
        status"Search For A Bootable Filesystem"

        file = a
        if bootfs then
            file = searchBootableFile(bootaddress)
        end

        if not file then
            for laddress in c.list"filesystem" do
                local lfile = searchBootableFile(laddress)
                if lfile then
                    bootaddress = laddress
                    file = lfile
                    break
                end
            end
        end
        if file then
            pleasWait()
            setDataPart(1, bootaddress)
            setDataPart(3, file)
            bootfs = c.proxy(bootaddress)
        else
            status("Bootable Filesystem Is Not Found", a, True, 1, 1)
            shutdown()
        end
    end

    ------------------------------------------boot

    if screen then resetpalette() end

    status("Boot To Drive " .. getLabel(bootaddress) .. " To File " .. file, 0xFFFFFF, a, a, 1)

    local file2, buffer = assert(bootfs.open(file, "rb")), ""
    while 1 do
        local read = bootfs.read(file2, math.huge)
        if not read then break end
        buffer = buffer .. read
    end
    bootfs.close(file2)

    p.beep(1000, .2)
    init = load(buffer, "=init")
end
init()