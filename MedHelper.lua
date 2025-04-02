script_name("Med Helper")
script_version_number("02.04.2025")
script_description("Universal helper for the Samp Advance RP Family")
script_author("Arseniy Samsonov")

require 'moonloader'

---------------------------------------- [= Requirets =] ----------------------------------------
local imgui = require 'mimgui'
local faicons = require('fAwesome6')
local ffi = require('ffi')
local encoding = require 'encoding'
encoding.default = 'CP1251'
local function u8(s) return encoding.UTF8:decode(s) end
local inicfg = require 'inicfg'
local vector = require("vector3d")

local PICKUP_POOL = 0
local NOTIFY_DISTANCE = 1.0  -- Дистанция в метрах
local CASINOnotify = false

local MainMenu = imgui.new.bool()
local changeStyle = imgui.new.bool(false)
local info = imgui.new.bool(false)
local settings = imgui.new.bool(false)
local actMenu = imgui.new.bool(false)
local sett = imgui.new.bool(false)
local analys = imgui.new.bool(false)

local rank = ""
local post = ""
local org = ""

local marker = nil
local ini

local RPHeal = false          -- Активность отыгровки
local playerId = nil          -- ID пациента
local price = nil             -- Цена услуги
local nick = nil              -- Ник игрока

local targetPlayerId = nil  -- ID целевого игрока
local targetPlayerNickname = ""  -- Ник целевого игрока
local disID = ""
local analysID = ""

local searchIsp = false
local nicknameIsp = ""
local page = 0

local sampev = require 'lib.samp.events'
commands = {"f", "r", "t", "n", "w", "s"}
bi = false

----------------------------------------[-= Json =-]----------------------------------------
local function json(filePath)
    local class = {}
    function class.save(tbl)
        if tbl then
            local F = io.open(filePath, 'w')
            F:write(encodeJson(tbl) or '{}')
            F:close()
            return true, 'ok'
        end
        return false, 'table = nil'
    end

    function class.load(defaultTable)
        if not doesFileExist(filePath) then
            class.save(defaultTable or {})
        end
        local F = io.open(filePath, 'r')
        local content = F:read('*a')
        local TABLE = decodeJson(content or '{}')
        F:close()
        for def_k, def_v in pairs(defaultTable) do
            if TABLE[def_k] == nil then
                TABLE[def_k] = def_v
            end
        end
        return TABLE
    end
    return class
end

createDirectory(getWorkingDirectory() .. '/config/')
local jPath = getWorkingDirectory() .. '/config/medhelper.json'
local j = json(jPath).load({
    autoLogin = false,
    autoPinCode = false,
    autoAnswer = false,
    RPsms = false,
    RPradio = false,
    RPfind = false,
    openChatT = false,
    noneOrg = false,
    cruiseControl = false,
    autoAnswerText = u8"Алло, я вас слушаю",
    autoORG = false,
    parol = "",
    pincode = "",
    Padialogid = 1, -- ID диалога для ввода пароля
    Pidialogid = 165,
}) 

local noneOrg = imgui.new.bool(j.noneOrg)
local RPradio = imgui.new.bool(j.RPradio)
local RPsms = imgui.new.bool(j.RPsms)
local RPfind = imgui.new.bool(j.RPfind)
local openChatT = imgui.new.bool(j.openChatT)
local cruiseControl = imgui.new.bool(j.cruiseControl)
local autoORG = imgui.new.bool(j.autoORG)

local autoLogin = imgui.new.bool(j.autoLogin)
local autoPinCode = imgui.new.bool(j.autoPinCode)

local Parol = imgui.new.char(256)
local PinCode = imgui.new.char(256)

----------------------------------------[-= Перенос строк =-]----------------------------------------
function sampev.onSendCommand(msg)
    if bi then bi = false; return end
    local cmd, msg = msg:match("/(%S*) (.*)")
    if msg == nil then return end
    -- cmd = cmd:lower()

    --Рация, радио, ООС чат, шепот, крик (с поддержкой переноса ООС-скобок)
    for i, v in ipairs(commands) do if cmd == v then
        local length = msg:len()
        if msg:sub(1, 2) == "((" then
            msg = string.gsub(msg:sub(4), "%)%)", "")
            if length > 80 then divide(msg, "/" .. cmd .. " (( ", " ))"); return false end
        else
            if length > 80 then divide(msg, "/" .. cmd .. " ", ""); return false end
        end
    end end

    --РП команды
    if cmd == "me" or cmd == "do" then
        local length = msg:len()
        if length > 75 then divide(msg, "/" .. cmd .. " ", "", "ext"); return false end
    end

    --SMS
    if cmd == "sms" then
        local msg = "{}" .. msg
        local number, _msg = msg:match("{}(%d+) (.*)")
        local msg = msg:sub(3)
        if _msg == nil then -- если номер не указан, ищется ближайшее полученное/отправленное сообщение
            for i = 1, 99 do                     -- номер берется из него
                local test = sampGetChatString(i):match("SMS: .* | .*: (.*)")
                if test ~= nil then number = string.match(test, ".* %[.*%.(%d+)%]") end
            end
        else msg = _msg end
        if number == nil then return end
        local length = msg:len()

        -- long SMS
        if length > 66 then divide(msg, "/sms " .. number .. " ", "", "sms"); return false end

        -- short SMS
        if length < 66 then bi = true; sampSendChat("/sms " .. number .. " " .. msg); return false end
    end
end

function sampev.onServerMessage(color, text)
    if color == -65281 and text:find(" %| Получатель: ") then
        return {bit.tobit(0xFFCC00FF), text}
    end
end

function sampev.onSendChat(msg) -- IC чат
    if bi then bi = false; return end
    local length = msg:len()
    if length > 90 then
        divide(msg, "", "")
        return false
    end
end

----------------------------------------[-= sampev.Диалоги =-]----------------------------------------
function sampev.onShowDialog(id, style, title, button1, button2, text)
    lua_thread.create(function()
        -- Обработка диалога для статистики игрока
        if id == 0 and title == u8"{FFCD00}Статистика игрока" then
            text = text:gsub("{......}", "")
            
            for line in text:gmatch("[^\n]+") do
                if line:find(u8'Должность:%s+(.+)') then
                    post = line:match(u8'Должность:%s+(.+)')
                end
                if line:find(u8'Организация:%s+(.+)') then
                    org = line:match(u8"Организация:%s+(.+)")
                end
                if line:find(u8'Ранг:%s+(.+)') then
                    rank = line:match(u8"Ранг:%s+(%d+)")
                end
            end
            return false
        end
        
        -- Обработка диалога для времени
        if id == 0 and title == u8"{FFCD00}Точное время - 0" then
            local play_time_h, play_time_m = 0, 0
            local afk_time_h, afk_time_m = 0, 0

            text = text:gsub("{......}", "")
        
            for line in text:gmatch("[^\n]+") do
                line = line:gsub("%s+", " ")
        
                local h, m = line:match(u8"Время в игре сегодня:%s*(%d+)%s*ч%s*(%d+)%s*мин")
                if h and m then
                    play_time_h, play_time_m = tonumber(h), tonumber(m)
                end
        
                local ah, am = line:match(u8"AFK за сегодня:%s*(%d+)%s*ч%s*(%d+)%s*мин")
                if ah and am then
                    afk_time_h, afk_time_m = tonumber(ah), tonumber(am)
                end
            end
        
            local total_play = play_time_h * 60 + play_time_m
            local total_afk = afk_time_h * 60 + afk_time_m
            local clean_time = math.max(total_play - total_afk, 0)
        
            local result_h = math.floor(clean_time / 60)
            local result_m = clean_time % 60
        if result_h == 0 then
            sampAddChatMessage(u8'{FF1493}[Med Helper]: {FFFFFF}Чистый онлайн за сегодня {FF1493}' .. result_m .. u8" минут", 0xFF1493)
        else
            sampAddChatMessage(u8'{FF1493}[Med Helper]: {FFFFFF}Чистый онлайн за сегодня {FF1493}' .. result_h .. u8" ч " .. result_m .. u8" мин", 0xFF1493)
        end
        end

        local crug = 0
        local totalLines = {0, 0, 0, 0, 0} -- Массив для хранения количества строк для каждого этапа
        
        -- Проверка диалога 415
        if autoORG[0] and id == 415 then
            sampSendDialogResponse(415, 1, 0) 
        end
        
        -- Обработка диалога 416 (по кнопкам)
        if autoORG[0] and id == 416 then
            if isDone then
                return
            end
            sampSendDialogResponse(416, 1, buttonIndex)
            wait(0)
            sampAddChatMessage(u8'Выбрана кнопка: ' .. (buttonIndex + 1), -2)
        
            buttonIndex = buttonIndex + 1
        
            if buttonIndex > 4 then
                buttonIndex = 0
                isDone = true
                return
            end
        end
        
        -- Обработка диалога 417 (считаем строки)
        if autoORG[0] and id == 417 then
            sampSendDialogResponse(417, 1, 0)
        
            local linesInText = 0
            for line in text:gmatch("[^\n]+") do
                linesInText = linesInText + 1
            end
        
            if text:find(u8"За сегодня не найдено никаких записей по этому параметру") then
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Найдено сообщение: 'За сегодня не найдено никаких записей по этому параметру'", 0xFF1493)
                linesInText = 0
            end
        
            -- Сохраняем количество строк для текущего этапа (crug)
            totalLines[crug] = linesInText
        
            -- Переход к следующему этапу, если не закончено
            crug = buttonIndex
            print(crug)
        
            -- Если все этапы завершены, выводим результат
            if crug >= 4 then
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Результаты подсчёта строк:", 0xFF1493)
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Принято: " .. totalLines[1], 0xFF1493)
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Уволено: " .. totalLines[2] + totalLines[3], 0xFF1493)
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Повышено: " .. totalLines[4], 0xFF1493)
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Понижено: " .. totalLines[5], 0xFF1493)
        
                -- Сброс счётчика, если нужно, или оставляем его для дальнейших циклов
                crug = 0
            else
                -- Переход к следующему этапу
                wait(1000)
                sampSendChat('/org')
            end
        end
        

        -- Ввод команды /org не должен скрывать диалог
        if autoLogin[0] and id == j.Padialogid then
            local password = j.parol or ""
            if password ~= "" then
                sampSendDialogResponse(id, 1, _, password)
                sampSendDialogResponse(id, 0, 0)
            end
        end

        if autoPinCode[0] and id == j.Pidialogid then
            local code = j.pincode or ""
            if code ~= "" then
                sampSendDialogResponse(id, 1, _, code)
                return false
            end
            return true
        end

        -- Обработка отчета и выбор кнопки
        if searchIsp and id == 191 then
            sampSendDialogResponse(191, 1, 5)  -- 1 - это выбор кнопки, 5 - это 6-й пункт (индекс 5, listitem с 0)
            sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Пожалуйста, подождите...", 0xFF1493)
        end

        if searchIsp and id == 66 then
            local nicks = extractNicks(text)
            local nickFound = false
            local index = 0
            
            for i, nick in ipairs(nicks) do
                if nick == nicknameIsp then
                    index = i - 1  -- index начинается с 0, поэтому уменьшаем на 1
                    nickFound = true
                    break
                end
            end
            
            if nickFound then
                sampSendDialogResponse(66, 1, index)
                sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Отчет найден: " .. nicks[index + 1], 0xFF1493)
                searchIsp = false
            else
                page = page + 1
                sampSendDialogResponse(66, 0)
            end
        end    
    end)
end

    
-- получить ники из /showall (для /isp)
function extractNicks(text)
    local nicks = {}
    for line in text:gmatch("[^\r\n]+") do
        local nick = line:match("%d+%.%s*([%w_]+)")
        if nick then
            table.insert(nicks, nick)
        end
    end
    return nicks
end

function sampev.onServerMessage(color, text)
    lua_thread.create(function()
        if text:find(u8"{80aaff}Свечи") then
            illines1 = true
        end
        if text:find(u8"{80aaff}Массажи") then
            illines2 = true
        end
        if text:find(u8"{80aaff}Приём антибиотиков") then
            illines3 = true
        end
        if text:find(u8"{80aaff}Ингаляция") then
            illines4 = true
        end
        if text:find(u8"{80aaff}Капельница") then
            illines5 = true
        end


        if text:find(u8"{ff9999}Сдача крови") then
            analys1 = true
        end
        if text:find(u8"{ff9999}Сдача мочи") then
            analys2 = true
        end
        if text:find(u8"{ff9999}Компьютерная томография") then
            analys3 = true
        end
        if text:find(u8"{ff9999}Магнитно-резонансная томография") then
            analys4 = true
        end
    end)
end

function divide(msg, beginning, ending, doing) -- разделение сообщения msg на два
    if doing == "sms" then limit = 57 else limit = 72 end
   
    -- -- -- ВЕРСИЯ С ПРИОРИТЕТОМ ТЕКСТА ДЛЯ ПЕРВОГО СООБЩЕНИЯ (ХУЕТА) -- -- --
    -- local one, two = string.match(msg:sub(limit), "(%S*) (.*)")
    -- if one == nil then one = "" end
    -- local one, two = msg:sub(1, limit - 1) .. one .. "...", "..." .. two
   
    -- ВЕРСИЯ С ПРИОРИТЕТОМ ТЕКСТА ДЛЯ ВТОРОГО СООБЩЕНИЯ (ЗБС НО НЕ РАБОТАЕТ) --
    -- local one, two = string.match(msg:sub(1, msg:len() - limit), "(.*) (.*)")
    -- if two == nil then two = "" end
    -- local one, two = one .. "...", "..." .. two .. msg:sub(msg:len() - limit + 1, msg:len())
   
    -- ВЕРСИЯ С ПРИОРИТЕТОМ ТЕКСТА ДЛЯ ВТОРОГО СООБЩЕНИЯ (ПОКА ЧТО РАБОТАЕТ) --
    local one, two = string.match(msg:sub(1, limit), "(.*) (.*)")
    if two == nil then two = "" end
    local one, two = one .. "...", "..." .. two .. msg:sub(limit + 1, msg:len())

    bi = true; sampSendChat(beginning .. one .. ending)
    if doing == "ext" then
        beginning = "/do "
        if two:sub(-1) ~= "." then two = two .. "." end
    end
    bi = true; sampSendChat(beginning .. two .. ending)
end

------------------------------------[-= Role Play =-]----------------------------------- 
function cmd_call(arg)
    local id = arg:match("^(%S+)$")
    if id then
        local playerId = tonumber(id)
        if playerId then
            if sampIsPlayerConnected(playerId) then
                local nickname = sampGetPlayerNickname(playerId)
                local myId = select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))
                myNick = sampGetPlayerNickname(myId)

                if nickname and myNick then
                    local function formatNickname(nick)
                        -- Разделяем ник на две части до и после "_"
                        local firstPart, secondPart = nick:match("([^_]+)_(.+)")
                        if firstPart and secondPart then
                            return firstPart:sub(1, 1) .. "." .. secondPart
                        else
                            return nick
                        end
                    end

                    nickname = formatNickname(nickname)
                    myNick = formatNickname(myNick)

                    targetNick = nickname

                    if myNick and targetNick then
                        sampSendChat('/call ' .. id)

                        sampSendChat(string.format(u8"/r Бригада состоящая из сотрудников %s и %s выехала на вызов!", myNick, targetNick))
                    else
                        sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Не удалось получить никнейм или инициалы игрока с ID {FF1493}' .. id .. '{FFFFFF}. Возможно, игрок не подключен.', 0xFF1493)
                    end
                else
                    sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Не удалось получить никнейм игрока с ID {FF1493}' .. id .. '{FFFFFF}. Возможно, игрок не подключен.', 0xFF1493)
                end
            else
                sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Игрок с ID {FF1493}' .. id .. ' {ffffff}не подключен к серверу', 0xFF1493)
            end
        else
            sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Неверный ID игрока. Используйте: {FF1493}/call [id игрока]', 0xFF1493)
        end
    else
        sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Используйте: {FF1493}/call [id игрока]', 0xFF1493)
    end
end


function cmd_invite(args)
    lua_thread.create(function()
        if rank >= 9 then
            local id = args:match("^(%S+)$")
            if id then
                local playerId = tonumber(id)
                if playerId then
                    local playerExists = sampIsPlayerConnected(playerId)
                    if playerExists then
                        local nickname = sampGetPlayerNickname(playerId)
                        if nickname then
                            nickname = nickname:gsub("_", " ")

                            sampSendChat(u8'/do На плечах висит рюкзак.', -1)
                            wait(900)
                            sampSendChat(u8'/me снял рюкзак, открыл его и достал форму и бейджик', -1)
                            wait(900)
                            sampSendChat(u8'/me передал вещи ' .. nickname, -1)
                            wait(900)
                            sampSendChat(u8'/invite ' .. id, -1)
                            wait(900)
                            sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи', -1)
                        else
                            sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Не удалось получить никнейм игрока с ID {FF1493}' .. id .. '{FFFFFF}. Возможно, игрок не подключен.', 0xFF1493)
                        end
                    else
                        sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Игрок с ID {FF1493}' .. id .. '{FFFFFF} не подключен к серверу.', 0xFF1493)
                    end
                else
                    sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Неверный ID игрока. Используйте: {FF1493}/invite [id игрока]', 0xFF1493)
                end
            else
                sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Используйте: {FF1493}/invite [id игрока]", 0xFF1493)
            end
        else
            sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Функция не доступна для вашей {FF1493}должности.', 0xFF1493)
        end
    end)
end

function cmd_changeskin(args)
    lua_thread.create(function()
        if rank >= 9 then

            local id = args:match("^(%S+)$")

            if not id then
                sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Используйте: {FF1493}/changeskin [id игрока]", 0xFF1493)
                return
            end

            local playerId = tonumber(id)
            
            if not playerId then
                sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Неверный ID игрока. Используйте: {FF1493}/changeskin [id игрока]', 0xFF1493)
                return
            end

            local playerExists = sampIsPlayerConnected(playerId)
            
            if playerExists then
                local nickname = sampGetPlayerNickname(playerId)
                if nickname then
                    nickname = nickname:gsub("_", " ")

                    sampSendChat(u8'/do На плечах висит рюкзак.', -1)
                    wait(900)
                    sampSendChat(u8'/me снял рюкзак, открыл его и достал форму и бейджик', -1)
                    wait(900)
                    sampSendChat(u8'/me передал вещи ' .. nickname, -1)
                    wait(900)
                    sampSendChat(u8'/changeskin ' .. id, -1)
                    wait(900)
                    sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи', -1)
                else
                    sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Не удалось получить никнейм игрока с ID {FF1493}' .. id .. '{FFFFFF}. Возможно, игрок не подключен.', 0xFF1493)
                end
            else
                sampSendChat('/changeskin ' .. id)
            end
        else
            sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Функция не доступна для вашей {FF1493}должности.', 0xFF1493)
        end
    end)
end

function fn(args)
    if args ~= "" then
        if noneOrg[0] then
            sampSendChat(string.format("/f (( %s ))", args))
        else
            sampSendChat(string.format("/f 1 (( %s ))", args))
        end
    end
end

function f(args)
    if RPradio[0] then
        sampSendChat(u8"/me достал рацию, зажал кнопку и что то сказал")
    end
    sampSendChat(string.format("/f %s", args))
end

function r(args)
    if RPradio[0] then
        sampSendChat(u8"/me достал рацию, зажал кнопку и что то сказал")
    end
    sampSendChat(string.format("/r %s", args))
end

function rn(args)
    if args ~= "" then
        sampSendChat(string.format("/r (( %s ))", args))
    end
end

function sms(args)
    if RPsms[0] then
        sampSendChat(u8"/me взял в руки телефон и начал что то печатать")
    end
    sampSendChat(string.format("/sms %s", args))
end

function find()
    if RPfind[0] then
        sampSendChat(u8"/me достал служебный КПК и проверил список сотрудников")
    end
    sampSendChat('/find')
end

function drive()
    lua_thread.create(function()
        if rank >= 9 then
            sampSendChat(u8"/r Вызываю эвакуатор для доставки служебного транспорта на парковку.")
            wait(1000)
            sampSendChat('/r (( /drive 5 sec ))')
            wait(4000)
            sampSendChat('/drive')
        else
            sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Функция не доступна для вашей {FF1493}должности.', 0xFF1493)
        end
    end)
end

function ud()
    lua_thread.create(function()
        local myname = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed)))
        sampSendChat(u8'/me легким движением руки достал из кармана удостоверение, показав его человеку на против')
        sampSendChat(u8'/do Имя: '.. myname ..' | Организация: ' .. org .. ' | Должность: '.. post)
    end)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges)
end)

local active_tab = 1  -- активная вкладка по умолчанию

imgui.OnFrame(function() return MainMenu[0] end, function(player)
    darkStyle()
    
    imgui.SetNextWindowPos(imgui.ImVec2(950, 500), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(700, 500), imgui.Cond.Always)
    imgui.Begin('Med Helper', MainMenu)

    -- Левая панель с кнопками
    imgui.BeginChild('LeftPanel', imgui.ImVec2(150, 0), true)

    local tabs = {
        {id = 1, label = faicons('users') .. u8' Общее'},
        {id = 2, label = faicons('spinner') .. u8' Авто-отыгровки'},
        {id = 3, label = faicons('car') .. u8' Транспорт'},
        {id = 4, label = faicons('receipt') .. u8' Справочник'},
        {id = 5, label = faicons('gear') .. u8' Настройки'},
    }

    for _, tab in ipairs(tabs) do
        if active_tab == tab.id then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.1, 0.1, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.15, 0.15, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.9, 0.2, 0.2, 1.0))
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.3, 0.3, 0.3, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.15, 0.15, 1.0))
        end

        if imgui.Button(tab.label, imgui.ImVec2(150, 60)) then
            active_tab = tab.id
        end

        imgui.PopStyleColor(3)
    end

    imgui.EndChild()

    -- правая панель для
    imgui.SameLine()
    imgui.BeginChild('RightPanel', imgui.ImVec2(0, 0), true)

    if active_tab == 1 then
        if imgui.Checkbox(u8"Не в организации", noneOrg) then j.noneOrg = noneOrg[0] json(jPath).save(j) end
        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 3) -- Смещаем иконку вправо на 3 пикселя
        imgui.Text(faicons('question'))
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8'при использовании команды /fn в чат не будет отправлятся лишняя "1", если вы не устроены в мэрии')
            imgui.EndTooltip()
        end
        if imgui.Checkbox(u8'Чат на T', openChatT) then j.openChatT = openChatT[0] json(jPath).save(j) end
        if imgui.Checkbox(u8'Cruise Control', cruiseControl) then j.cruiseControl = cruiseControl[0] json(jPath).save(j) end
        if imgui.Checkbox(u8'Автоотчет', autoORG) then j.autoORG = autoORG[0] json(jPath).save(j) end
        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 3) -- Смещаем иконку вправо на 3 пикселя
        imgui.Text(faicons('question'))
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8'при вводе комадны /org скрипт автоматически выдаст информацию по количеству действий')
            imgui.EndTooltip()
        end
    elseif active_tab == 2 then
        if imgui.Checkbox(u8"Role-Play рация", RPradio) then j.RPradio = RPradio[0] json(jPath).save(j) end
        if imgui.Checkbox(u8"Role-Play смс", RPsms) then j.RPsms = RPsms[0] json(jPath).save(j) end
        if imgui.Checkbox(u8"Role-Play финд", RPfind) then j.RPfind = RPfind[0] json(jPath).save(j) end
    elseif active_tab == 3 then
        imgui.Text(u8'Транспорт')
    elseif active_tab == 4 then
        if imgui.CollapsingHeader(faicons('book') .. u8'Список команд и функций') then
            imgui.Text(faicons('inbox') .. u8" Общее")
            imgui.Text(u8"/mh - меню скрипта")
            imgui.Text(u8"/medhelp [id] [price] - вылечить пациента (по RP)")
            imgui.Text(u8"/drone - включить/выключить дрон (CamHack, свободный полет)")
            imgui.Text(u8"/his [id] - fast history по id игрока")
            imgui.Text(u8"/isp [id] - поиск отчета игрока по id")
            imgui.Text(u8"/rec [sec] - переподключение к серверу (sec = 15 если не выставлено)")
            imgui.Text(faicons('comments') .. u8" Коммуникация")
            imgui.Text(u8"/rn [text] - отправить ООС сообщение в рацию подразделения (добавятся ООС скобки)")
            imgui.Text(u8"/fn [text]- отправить ООС сообщение в рацию организации (добавятся ООС скобки)")
            imgui.Text(u8"/sms [text] - отправить сообщение последнему собеседнику sms (без указания номера)")
            imgui.Text(faicons('house') .. u8" Поиск домов")
            imgui.Text(u8"/fh [number] - поставить метку на дом по его номеру")
            imgui.Text(u8"/rm - убрать метку с дома")
        end
    elseif active_tab == 5 then
        imgui.SetCursorPos(imgui.ImVec2(245, 27))
        if imgui.Checkbox("", autoLogin) then j.autoLogin = autoLogin[0] json(jPath).save(j) end
        imgui.PopID()
        imgui.SetCursorPos(imgui.ImVec2(270, 30))
        imgui.TextColored(autoLogin[0] and imgui.ImVec4(0.0, 1.0, 0.0, 1.0) or imgui.ImVec4(1.0, 0.0, 0.0, 1.0), 
        autoLogin[0] and u8'Вкл' or u8'Выкл')
        imgui.SetCursorPos(imgui.ImVec2(270, 50))
        imgui.TextColored(autoPinCode[0] and imgui.ImVec4(0.0, 1.0, 0.0, 1.0) or imgui.ImVec4(1.0, 0.0, 0.0, 1.0), 
        autoPinCode[0] and u8'Вкл' or u8'Выкл')

        imgui.SetCursorPos(imgui.ImVec2(245, 50))
        if imgui.Checkbox("", autoPinCode) then j.autoPinCode = autoPinCode[0] json(jPath).save(j) end     
        imgui.SetCursorPos(imgui.ImVec2(10, 10))
        imgui.TextDisabled(u8'Автоматический ввод')
        imgui.PushItemWidth(180)
        if imgui.InputTextWithHint(u8'Пароль', u8'Введите ваш пароль', Parol, 256) then 
             if autoLogin[0] then
                j.parol = u8:decode(ffi.string(Parol)) json(jPath).save(j) 
            end
        end
        if imgui.InputTextWithHint(u8'Пин-код', u8'Введите ваш пинкод банка', PinCode, 256) then
            if autoPinCode[0] then
                j.pincode = u8:decode(ffi.string(PinCode)) json(jPath).save(j) 
            end
        end
        imgui.PopItemWidth()
    end

    imgui.EndChild()
    imgui.End()
end)

imgui.OnFrame(function() return sett[0] end, function()
    local X, Y = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(300, 100), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(X / 2 - 200, Y / 2 - 139), imgui.Cond.FirstUseEver)
    if imgui.Begin(u8'Окно а хули не окно?', sett, imgui.Cond.FirstUseEver) then
        darkStyle()
        imgui.Separator()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 120)
        imgui.Text(u8'Общее')
        if imgui.Button(u8'Вылечить от ангины', imgui.ImVec2(-1, 0)) then
            lua_thread.create(function()
                sampSendChat(u8'/do На плечах висит рюкзак.')
                wait(900)
                sampSendChat(u8'/me снял рюкзак, открыл его и достал форму и бейджик')
                wait(900)
                sampSendChat(u8'/me передал вещи ' .. targetPlayerNickname)
                wait(900)
                sampSendChat('/changeskin ' .. targetPlayerId)
                wait(900)
                sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи')
            end)
        end
        imgui.Separator()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 120)
        imgui.Text(u8'Лидерам')
        if imgui.Button(u8'Поменять форму', imgui.ImVec2(-1, 0)) then
            lua_thread.create(function()
                sampSendChat(u8'/do На плечах висит рюкзак.')
                wait(900)
                sampSendChat(u8'/me снял рюкзак, открыл его и достал форму и бейджик')
                wait(900)
                sampSendChat(u8'/me передал вещи ' .. targetPlayerNickname)
                wait(900)
                sampSendChat('/changeskin ' .. targetPlayerId)
                wait(900)
                sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи')
            end)
        end
    
        if imgui.Button(u8'Принять в организацию', imgui.ImVec2(-1, 0)) then
            lua_thread.create(function()
                sampSendChat(u8'/do На плечах висит рюкзак.')
                wait(900)
                sampSendChat(u8'/me снял рюкзак, открыл его и достал форму и бейджик')
                wait(900)
                sampSendChat(u8'/me передал вещи ' .. targetPlayerNickname)
                wait(900)
                sampSendChat(u8'/invite ' .. targetPlayerId)
                wait(900)
                sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи')
            end)
        end
    
        if imgui.Button(u8'Повысить ранг', imgui.ImVec2(-1, 0)) then
            lua_thread.create(function()
                sampSendChat(u8'/do Новый бейджик сотрудника в правом кармане.')
                wait(900)
                sampSendChat(u8'/me достал новый бейджик из кармана')
                wait(900)
                sampSendChat(u8'/me передал его сотруднику ' .. targetPlayerNickname)
                wait(900)
                sampSendChat(u8'/rang ' .. targetPlayerId .. ' +')
                wait(900)
                sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи')
            end)
        end
    
        if imgui.Button(u8'Понизить ранг', imgui.ImVec2(-1, 0)) then
            lua_thread.create(function()
                sampSendChat(u8'/do Новый бейджик сотрудника в правом кармане.')
                wait(900)
                sampSendChat(u8'/me достал новый бейджик из кармана')
                wait(900)
                sampSendChat(u8'/me передал его сотруднику ' .. targetPlayerNickname)
                wait(900)
                sampSendChat(u8'/rang ' .. targetPlayerId .. ' -')
                wait(900)
                sampSendChat(u8'/me закрыл рюкзак и повесил его обратно на плечи')
            end)
        end
        imgui.SameLine()
    end
    imgui.End()
end)

------------------------------------------- Новости --------------------------------------------
local inputGnewsText1 = imgui.new.char(256)
local inputGnewsText2 = imgui.new.char(256)
local inputGnewsText3 = imgui.new.char(256)
local showGnewsWindow = imgui.new.bool(false)

local sendAtTime = imgui.new.bool(false)
local timeDelay = imgui.new.int(1)
local confirmationMessage = ""

imgui.OnFrame(function() return showGnewsWindow[0] end, function()
    local X, Y = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(415, 279), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(X / 2 - 207, Y / 2 - 139), imgui.Cond.FirstUseEver)

    darkStyle()

    imgui.Begin(u8"Добавление новости", showGnewsWindow)
        imgui.InputTextWithHint(u8'##gnewsInput1', u8'Введите первую новость', inputGnewsText1, 256)
        imgui.InputTextWithHint(u8'##gnewsInput2', u8'Введите вторую новость', inputGnewsText2, 256)
        imgui.InputTextWithHint(u8'##gnewsInput3', u8'Введите третью новость', inputGnewsText3, 256)

        imgui.Checkbox(u8"Отправка по времени", sendAtTime)

        if sendAtTime[0] then
            imgui.SliderInt(u8"Время (в минутах)", timeDelay, 1, 59)
        end

        if sendAtTime[0] then
            local currentTime = os.date("*t")
            local targetMinute = (currentTime.min + timeDelay[0]) % 60
            local targetHour = currentTime.hour

            if currentTime.min + timeDelay[0] >= 60 then
                targetMinute = (currentTime.min + timeDelay[0]) % 60
                targetHour = (currentTime.hour + 1) % 24
            end

            confirmationMessage = string.format(u8"Новость будет отправлена в %02d:%02d", targetHour, targetMinute)
            imgui.Text(u8(confirmationMessage))
        end

        if imgui.Button(u8"Отправить", imgui.ImVec2(-1, 0)) then
            local news1 = u8:decode(ffi.string(inputGnewsText1))
            local news2 = u8:decode(ffi.string(inputGnewsText2))
            local news3 = u8:decode(ffi.string(inputGnewsText3))

            showGnewsWindow[0] = false

            -- Проверка на 2 строки (запрещено)
            if (news1 ~= '' and news2 ~= '') and news3 == '' then
                sampAddChatMessage(u8'Вы не можете отправить 2 строки новости. Только 1 или 3', -2)
                return
            end  

            local newsCount = 0
            if news1 ~= '' then newsCount = newsCount + 1 end
            if news2 ~= '' then newsCount = newsCount + 1 end
            if news3 ~= '' then newsCount = newsCount + 1 end

            local sendMessage = ""
            local sendHour, sendMinute = os.date("*t").hour, os.date("*t").min

            if sendAtTime[0] then
                sendMinute = (sendMinute + timeDelay[0]) % 60
                if os.date("*t").min + timeDelay[0] >= 60 then
                    sendHour = (sendHour + 1) % 24
                end
            end

            if newsCount == 1 then
                sendMessage = sendAtTime[0] and string.format(u8"в %02d:%02d кину одну", sendHour, sendMinute) or "кину одну"
            elseif newsCount == 3 then
                sendMessage = sendAtTime[0] and string.format(u8"в %02d:%02d кину три", sendHour, sendMinute) or "кину три"
            end

            lua_thread.create(function()
                if sendMessage ~= "" then
                    sampAddChatMessage(sendMessage, -1)
                    wait(3000)
                end

                if sendAtTime[0] then
                    local currentTime = os.date("*t")
                    local targetMinute = (currentTime.min + timeDelay[0]) % 60
                    local targetHour = currentTime.hour

                    if currentTime.min + timeDelay[0] >= 60 then
                        targetMinute = (currentTime.min + timeDelay[0]) % 60
                        targetHour = (currentTime.hour + 1) % 24
                    end

                    local targetTime = os.time({year=currentTime.year, month=currentTime.month, day=currentTime.day, hour=targetHour, min=targetMinute, sec=0})
                    local currentTimeInSecs = os.time(currentTime)

                    local waitTime = targetTime - currentTimeInSecs
                    wait(waitTime * 1000)
                end

                if news1 and news1 ~= '' then
                    sampAddChatMessage("/gnews " .. news1)
                    wait(900)
                end
                if news2 and news2 ~= '' then
                    sampAddChatMessage("/gnews " .. news2)
                    wait(900)
                end
                if news3 and news3 ~= '' then
                    sampAddChatMessage("/gnews " .. news3)
                    wait(900)
                end              
            end)
        end

        if imgui.CollapsingHeader(u8'Отправка по шаблонам') then
            if imgui.Button(u8'Собеседование (начало-БЛС)', imgui.ImVec2(400, 0)) then
                inputGnewsText1 = ffi.new("char[?]", #(u8'Уважаемые жители, минуточку внимания!') + 1, u8'Уважаемые жители, минуточку внимания!')
                inputGnewsText2 = ffi.new("char[?]", #(u8'Сейчас пройдет собеседование в Больницу ш. Los-Santos.') + 1, u8'Сейчас пройдет собеседование в Больницу ш. Los-Santos.')
                inputGnewsText3 = ffi.new("char[?]", #(u8'Прихватите документы, и не забудьте мед. карту! Ждем GPS 3-12') + 1, u8'Прихватите документы, и не забудьте мед. карту! Ждем GPS 3-12')
            end
        end

    imgui.End()
end)

-- получить ник по ID
function getPlayerName(playerId)
    local name = nil
    for i = 0, 1000 do -- до 1000 игроков
        if sampIsPlayerConnected(i) and i == playerId then
            name = sampGetPlayerNickname(i)
            break
        end
    end
    return name
end

function cmd_medhelp(args)
    lua_thread.create(function()
        local inputs = {}
        for arg in string.gmatch(args, "%S+") do
            table.insert(inputs, arg)
        end

        if #inputs ~= 2 then
            sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Неправильный формат команды. Используйте: {FF1493}/medhelp [id] [цена].", 0xFF1493)
            return
        end

        playerId = tonumber(inputs[1])
        price = inputs[2]

        if playerId and playerId >= 0 and playerId < 1000 then
            local playerName = getPlayerName(playerId)
            nick = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))):gsub("_", " ") -- "_" на " " в нике чтоб без мг
        
            sampSendChat(string.format(u8"Здравствуйте, я Ваш лечащий врач %s. Что Вас беспокоит?", nick))
            wait(1000)
            sampAddChatMessage(u8'{FF1493}[Med Helper]: {FFFFFF}Нажмите {FF1493}F3 {FFFFFF}для продолжения или {FF1493}F1 {FFFFFF}для отмены.', 0xFF1493)

            RPHeal = true

        else
            sampSendChat(u8"{FF1493}[Med Helper]: {FFFFFF}ID должен быть числовым и в пределах допустимых значений (0-999).", 0xFF1493)
        end
    end)
end

function fastHistory(playerId)
    local id = tonumber(playerId)
    
    if id == nil or id <= 0 or id >=1000 then
        sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Укажите корректный {FF1493}ID {FFFFFF}игрока! {FF1493}(от 0 до 1000)', 0xFF1493)
        return
    end

    local nickname = sampGetPlayerNickname(id)

    if nickname == nil or nickname == '' then
        sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Игрок с таким {FF1493}ID {FFFFFF}не найден!', 0xFF1493)
        return
    end

    local command = '/history ' .. nickname
    sampSendChat(command)
end

------------------------------------[-= Cruise Control =-]----------------------------------- 
local ccSpeed = 0
local ccFont = nil
local ccConfig = { x = 100, y = 100, size = 20 }
local keyUp = 0x6A       -- NumPad +
local keyDown = 0x6D     -- NumPad -
local ccIniPath = getGameDirectory() .. "/moonloader/MedHelper/ccontrol.ini"
local speedChangeDelay = 50

local function loadCCConfig()
    local file = io.open(ccIniPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("(%w+)=(.+)")
            if key and value then ccConfig[key] = tonumber(value) end
        end
        file:close()
    else
        local f = io.open(ccIniPath, "w")
        if f then
            for k, v in pairs(ccConfig) do
                f:write(string.format("%s=%d\n", k, v))
            end
            f:close()
        end
    end
end

local function saveCCConfig()
    local file = io.open(ccIniPath, "w")
    if file then
        for k, v in pairs(ccConfig) do
            file:write(string.format("%s=%d\n", k, v))
        end
        file:close()
    end
end

local function drawInfoText()
    local text = ("%.0f км/ч"):format(ccSpeed * 2)
    renderFontDrawText(ccFont, text, ccConfig.x, ccConfig.y, 0xFFFF0000)
end

local function smoothlyChangeSpeed(amount)
    local targetSpeed = math.max(0, ccSpeed + amount)
    while ccSpeed ~= targetSpeed do
        ccSpeed = ccSpeed + (amount > 0 and 1 or -1)
        wait(speedChangeDelay)
    end
end

function rm()
	removeBlip(marker)
	sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Метка на дом {FF0000}Убрана", 0xFF1493)
end

function fh(num)
	if #num == 0 then
		sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Укажите номер дома: {FF1493}/fh [house id]", 0xFF1493)
	else
		local id = tonumber(num)
		if not id then
			sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Ввдите корректный номер дома {FF1493}Без символов и букв", 0xFF1493)
			return false
		end
		if not ini[id] then
			sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Указанного дома нет/Координат этого дома нет в файле {FF1493}house.ini", 0xFF1493)
			return false
		else
			if marker then
				removeBlip(marker)	
			end
			sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Метка на дом {00FF00}поставлена", 0xFF1493)
			marker = addBlipForCoord(ini[id].x, ini[id].y, ini[id].z)
			changeBlipScale(marker, 3) --Размер метки
			changeBlipColour(marker, 0xFF00FFFF) --Цвет метки
		end
	end
end

function dis(arg)
    disID = arg
    disID = sampGetPlayerNickname(id):gsub("_", " ")
    sampAddChatMessage('/dis ' .. arg)
end

function analysis(arg)
    analysID = arg
    analysID = sampGetPlayerNickname(id):gsub("_", " ")
    sampAddChatMessage('/analysis ' .. arg)
end

function onScriptTerminate(script, exit)
	if script == thisScript() and marker then
		removeBlip(marker)
	end
end

function main()
    while not isSampAvailable() do
        wait(100)
    end

    sampSendChat('/st')

    sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Med Helper обновлен успешно! Версия {FF1493}1.0', 0xFF1493)
    sampRegisterChatCommand("medhelp", cmd_medhelp)
    sampRegisterChatCommand('mh', function() MainMenu[0] = not MainMenu[0] end)
    sampRegisterChatCommand('gmenu', function()
        if rank ~= 10 then sampAddChatMessage(u8'[Med Helper]: {FFFFFF}Данная функция доступна только лидерам', 0xFF1493) return end
        showGnewsWindow[0] = not showGnewsWindow[0]
    end)
    

    sampRegisterChatCommand('fn', fn)
    sampRegisterChatCommand('rn', rn)
    sampRegisterChatCommand('f', f)
    sampRegisterChatCommand('r', r)
    sampRegisterChatCommand('sms', sms)
    sampRegisterChatCommand('drone', OnDrone)
    sampRegisterChatCommand('fh', fh)
    sampRegisterChatCommand('rm', rm)
    sampRegisterChatCommand('find', find)
    sampRegisterChatCommand('isp', isp)
    sampRegisterChatCommand('drive', drive)
    sampRegisterChatCommand('changeskin', cmd_changeskin)
    sampRegisterChatCommand('call', cmd_call)
    sampRegisterChatCommand('ud', ud)
    sampRegisterChatCommand('dis', dis)
    sampRegisterChatCommand('org', org)
    sampRegisterChatCommand('his', fastHistory)
    sampRegisterChatCommand('analysis', dis)

    sampRegisterChatCommand('rec', reconnect)
    if not doesFileExist("moonloader/config/houses.ini") then

        sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Нет файла {FF1493}houses.ini в папке moonloader/config!", 0xFF1493)
    else
        ini = inicfg.load({}, 'moonloader/config/houses.ini')
    end

    drone = 0  
    speed = 1.0
    angZ, angY, posX, posY, posZ = 0.0, 0.0, 0.0, 0.0, 0.0

    while true do
        wait(0)

        if res and time ~= nil then
			sampDisconnectWithReason(quit)
			wait(time*1000)
			sampSetGamestate(1)
			res= false
			else if res and time == nil then
				sampDisconnectWithReason(quit)
				wait(15500)
				sampSetGamestate(1)
				res= false
			end
		end

        checkPlayerPickupProximity()

        if drone == 1 then
            CameraAndDrone()
            DroneSpeed()
        end
        if isKeyDown(VK_RETURN) then
            if drone == 1 then
                OffDrone()
            end
        end

        if RPHeal and isKeyJustPressed(VK_F3) then
            sampSendChat(u8"/me выслушал пациента и поставил ему диагноз")
            wait(1000)
            sampSendChat(u8"/do Через плечо надета медицинская сумка.")
            wait(1000)
            sampSendChat(u8"/me правой рукой залез в сумку и достал нужный препарат")
            wait(1000)
            sampSendChat(u8"/me легким движением руки передал препарат пациенту")
            wait(100)
            sampSendChat(string.format("/medhelp %d %s", playerId, price))
            wait(3000)
            sampSendChat(u8"Всего доброго! Не болейте больше.")
            RPHeal = false
        end
        if RPHeal and isKeyJustPressed(VK_F1) then
            RPHeal = false
        end

        if illines1 and disID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', disID))
            illines1 = false
        end
        if illines2 and disID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', disID))
            illines2 = false
        end
        if illines3 and disID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', disID))
            illines3 = false
        end
        if illines4 and disID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', disID))
            illines4 = false
        end
        if illines5 and disID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', disID))
            illines5 = false
        end

        
        if analys1 and analysID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал пациенту %s свечи от геморроя и направил на процедуру', analysID))
            analys1 = false
        end
        if analys1 and analysID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал %s направление на прохождение анализа крови', analysID))
            analys1 = false
        end
        if analys2 and analysID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал %s направление на прохождение анализа мочи', analysID))
            analys2 = false
        end
        if analys3 and analysID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал %s направление на прохождение КТ', analysID))
            analys3 = false
        end
        if analys4 and analysID ~= "" then
            wait(100)
            sampSendChat(string.format(u8'/me выписал %s направление на прохождение МРТ', analysID))
            analys4 = false
        end
        
        imgui.ShowCursor = sett[0]
        imgui.Process = sett[0]
        
        PICKUP_POOL = sampGetPickupPoolPtr()

        if isKeyJustPressed(82) and isKeyJustPressed(2) then
            local validtar, pedtar = getCharPlayerIsTargeting(playerHandle)
            if validtar and doesCharExist(pedtar) then
                local result, id = sampGetPlayerIdByCharHandle(pedtar)
                if result then
                    targetPlayerId = id
                    targetPlayerNickname = sampGetPlayerNickname(id):gsub("_", " ")
                    sett[0] = true
                end
            end
        end
        if isKeyJustPressed(VK_T) and openChatT[0] then
            sampSetChatInputEnabled(true)
        end

        -- Круиз Контроль: выполняется только если включен чекбокс cruiseControl и игрок в авто
        if cruiseControl[0] and isCharInAnyCar(playerPed) then
            if not ccFont then
                loadCCConfig()
                ccFont = renderCreateFont("Arial", ccConfig.size, 9)
                ccSpeed = getCarSpeed(storeCarCharIsInNoSave(playerPed))
            end
            drawInfoText()
            if isKeyDown(keyUp) then smoothlyChangeSpeed(1) end
            if isKeyDown(keyDown) then smoothlyChangeSpeed(-1) end
            if getCarSpeed(storeCarCharIsInNoSave(playerPed)) < ccSpeed then
                writeMemory(0xB73458 + 0x20, 1, 255, false)
            end
        end
    end
end

function reconnect(param)
	time = tonumber(param)
	res = true
end

function isp(nickname)
    if not nickname or nickname == "" then
        sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Использование: {FF1493}/isp [nickname]", 0xFF1493)
        return
    else
        nicknameIsp = nickname
        sampSendChat("/showall")
        searchIsp = true
        page = 0
    end
end

function org()
    if autoORG[0] then
        buttonIndex = 0
        isDone = false
    end
    sampSendChat('/org')
end

function checkPlayerPickupProximity()
    local playerPos = vector(getCharCoordinates(PLAYER_PED))
    for id = 0, 4096 do
        local PICKUP_HANDLE = sampGetPickupHandleBySampId(id)
        if PICKUP_HANDLE ~= 0 then
            local pickupPos = vector(getPickupCoordinates(PICKUP_HANDLE))
            local distance = getDistanceBetweenCoords3d(playerPos.x, playerPos.y, playerPos.z, pickupPos.x, pickupPos.y, pickupPos.z)
            if not CASINOnotify and distance <= NOTIFY_DISTANCE then
                notifyPlayer()
            end
        end
    end
end

function notifyPlayer()
    sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Уважаемый игрок! Помните, что игра в казино в рабочее время может быть наказуема в...", 0xFF1493)
    sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}...IC-формате (или администрацией, если вы лидер). Кроме того, помните, что вы можете потерять все свои сбережения!", 0xFF1493)
    sampAddChatMessage(u8"{FF1493}[Med Helper]: {FFFFFF}Играйте с умом и не делайте необдуманных ставок. Мы категорически против казино!", 0xFF1493)
    CASINOnotify = true
end

-- function autoAnswer()
--     sampSendChat('/p', -1)
--     wait(900)

--     if autoP[0] then
--         local answerText = j.autoPText or "Алло, я вас слушаю"
--         sampSendChat(answerText, -1)
--     end
-- end
----------------------------------------[-= Style =-]---------------------------------------- 
function darkStyle()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    -- Закругления и отступы
    style.WindowRounding = 7.0
    style.FrameRounding = 4.0
    style.ItemSpacing = imgui.ImVec2(1.0, 3.0)
    style.ScrollbarSize = 12.0
    style.ScrollbarRounding = 6.0
    style.GrabMinSize = 8.0
    style.GrabRounding = 4.0
    -- style.FramePadding = imgui.ImVec2(10, 12)  -- Размер кнопок, чекбоксов, инпутов

    -- Цвета фона и текста
    colors[clr.WindowBg] = ImVec4(0.10, 0.10, 0.10, 1.00)
    colors[clr.FrameBg] = ImVec4(0.20, 0.20, 0.20, 0.54)
    colors[clr.FrameBgHovered] = ImVec4(0.25, 0.25, 0.25, 0.45)
    colors[clr.FrameBgActive] = ImVec4(0.30, 0.30, 0.30, 0.67)
    colors[clr.Text] = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.Separator] = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[clr.TitleBg] = ImVec4(0.15, 0.15, 0.15, 1.00)
    colors[clr.TitleBgActive] = ImVec4(0.20, 0.20, 0.20, 1.00)

    -- стиль кнопок (нейтральных)
    colors[clr.Button] = ImVec4(0.2, 0.2, 0.2, 1.0)
    colors[clr.ButtonHovered] = ImVec4(0.3, 0.3, 0.3, 1.0)
    colors[clr.ButtonActive] = ImVec4(0.15, 0.15, 0.15, 1.0)

    -- активные (выделенных) кнопок
    colors[clr.Header] = ImVec4(0.8, 0.1, 0.1, 1.0)
    colors[clr.HeaderHovered] = ImVec4(0.85, 0.15, 0.15, 1.0)
    colors[clr.HeaderActive] = ImVec4(0.9, 0.2, 0.2, 1.0)
end


function purpleStyle()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    imgui.StyleColorsDark()

    style.WindowRounding = 5.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.FrameRounding = 5.0
    style.ItemSpacing = imgui.ImVec2(10.0, 5.0)
    style.ScrollbarSize = 12.0
    style.ScrollbarRounding = 6.0
    style.GrabMinSize = 7.0
    style.GrabRounding = 3.0

    colors[clr.FrameBg] = ImVec4(0.8, 0.4, 0.9, 0.6)
    colors[clr.FrameBgHovered] = ImVec4(0.85, 0.45, 0.95, 0.55)
    colors[clr.FrameBgActive] = ImVec4(0.9, 0.5, 1.0, 0.7)
    colors[clr.TitleBg] = ImVec4(0.1, 0.1, 0.1, 1.00)
    colors[clr.TitleBgActive] = ImVec4(0.85, 0.45, 0.95, 1.00)
    colors[clr.Button] = ImVec4(0.8, 0.4, 0.9, 0.7)
    colors[clr.ButtonHovered] = ImVec4(0.85, 0.45, 0.95, 0.85)
    colors[clr.ButtonActive] = ImVec4(0.9, 0.5, 1.0, 1.0)
    colors[clr.Text] = ImVec4(1.0, 1.0, 1.0, 1.0)
    colors[clr.WindowBg] = ImVec4(0.2, 0.1, 0.2, 0.95)

    colors[clr.Header] = ImVec4(0.8, 0.4, 0.9, 0.7)
    colors[clr.HeaderHovered] = ImVec4(0.85, 0.45, 0.95, 0.85)
    colors[clr.HeaderActive] = ImVec4(0.9, 0.5, 1.0, 1.0)

    colors[clr.SliderGrab] = ImVec4(0.8, 0.4, 0.9, 0.7)
    colors[clr.SliderGrabActive] = ImVec4(0.85, 0.45, 0.95, 0.85)
end

----------------------------------------[-= Drone =-]---------------------------------------- 
function OnDrone()
    if drone == 0 then
        displayRadar(false)
        displayHud(false)
        posX, posY, posZ = getCharCoordinates(playerPed)
        angZ = getCharHeading(playerPed) * -1.0
        angY = 0.0
        setFixedCameraPosition(posX, posY, posZ, 0.0, 0.0, 0.0)
        lockPlayerControl(true)
        drone = 1
        sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Режим дрона активирован. {FF1493}Enter {FFFFFF}чтобы выйти, {FF1493}+/- {FFFFFF}скорость", 0xFF1493)
    else
        OffDrone()
    end
end

function CameraAndDrone()
    if drone == 1 then
        Camera()
        moveDrone()
        CameraAtDrone()
    end
end

function Camera()
    local offMouX, offMouY = getPcMouseMovement()
    angZ = (angZ + offMouX / 4.0) % 360.0
    angY = math.min(89.0, math.max(-89.0, angY + offMouY / 4.0))
end

function moveDrone()
    if drone == 1 then
        local radZ = math.rad(angZ)
        local radY = math.rad(angY)

        local forwardX = math.sin(radZ) * math.cos(radY)
        local forwardY = math.cos(radZ) * math.cos(radY)
        local forwardZ = math.sin(radY)

        local rightX = math.sin(radZ + math.pi / 2)
        local rightY = math.cos(radZ + math.pi / 2)

        if isKeyDown(VK_W) then
            posX = posX + forwardX * speed
            posY = posY + forwardY * speed
            posZ = posZ + forwardZ * speed
        end
        if isKeyDown(VK_S) then
            posX = posX - forwardX * speed
            posY = posY - forwardY * speed
            posZ = posZ - forwardZ * speed
        end
        if isKeyDown(VK_A) then
            posX = posX - rightX * speed
            posY = posY - rightY * speed
        end
        if isKeyDown(VK_D) then
            posX = posX + rightX * speed
            posY = posY + rightY * speed
        end
        if isKeyDown(VK_SPACE) then
            posZ = posZ + speed
        end
        if isKeyDown(VK_SHIFT) then
            posZ = posZ - speed
        end
    end
end

function CameraAtDrone()
    if drone == 1 then
        local radZ = math.rad(angZ)
        local radY = math.rad(angY)

        local camX = posX + math.sin(radZ) * math.cos(radY)
        local camY = posY + math.cos(radZ) * math.cos(radY)
        local camZ = posZ + math.sin(radY)

        setFixedCameraPosition(posX, posY, posZ, 0.0, 0.0, 0.0)
        pointCameraAtPoint(camX, camY, camZ, 2)
    end
end

function DroneSpeed()
    if drone == 1 then
        if isKeyDown(187) then
            speed = speed + 0.01
            printStringNow(string.format("Speed: %.2f", speed), 1000)
        end

        if isKeyDown(189) then
            speed = speed - 0.01
            if speed < 0.01 then speed = 0.01 end
            printStringNow(string.format("Speed: %.2f", speed), 1000)
        end
    end
end

function OffDrone()
    displayRadar(true)
    displayHud(true)
    lockPlayerControl(false)
    restoreCameraJumpcut()
    setCameraBehindPlayer()
    drone = 0
    sampAddChatMessage(u8"[Med Helper]: {FFFFFF}Режим дрона отключён.", 0xFF1493)
end
