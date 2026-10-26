function rootClean(v)
    if type(v) == 'function' then
        pcall(v)
        return
    end
    if type(v) == 'table' then
        for _, value in pairs(v) do
            rootClean(value)
        end
        table.clear(v)
        return
    end
    pcall(function() task.cancel(v) end)
    pcall(function() v:Stop()       end)
    pcall(function() v:Disconnect() end)
    pcall(function() v:Cancel()     end)
    pcall(function() v:Disable()    end)
    pcall(function() v:Remove()     end)
    pcall(function() v:Destroy()    end)
end

if shared.CleanupTable then
    for _, v in shared.CleanupTable do
        rootClean(v)
    end
end

shared.CleanupTable = {}

function clean(obj, boolFunc)
    table.insert(shared.CleanupTable, obj)
    if boolFunc ~= nil then
        task.spawn(function()
            pcall(function()
                repeat task.wait() until boolFunc() == false
                rootClean(obj)
            end)
        end)
    end
    return obj
end

local players = game:GetService('Players')
local httpService = game:GetService('HttpService')

local player = players.LocalPlayer

local opts = ({...})[1] or {}
local topic = opts.topic
local debugging = opts.debug or false

local Net = {}

do
    local baseUrl = 'https://ntfy.sh/' .. topic
    local requestFn = request or http_request or (syn and syn.request) or (http and http.request)
    local handlers = {}
    local running = true

    clean(function()
        running = false
    end)

    function Net.receive(kind, callback)
        handlers[kind] = callback
    end

    Net.on = Net.receive

    function Net.send(kind, payload)
        if not requestFn then
            if debugging then
                print('ntfy: no request function')
            end
            return
        end

        task.spawn(function()
            local ok, response = pcall(requestFn, {
                Url = baseUrl,
                Method = 'POST',
                Body = httpService:JSONEncode({
                    type = kind,
                    from = player.Name,
                    payload = payload,
                }),
            })
            if debugging then
                print('ntfy send', kind, ok, ok and response and (response.StatusCode or response.Status))
            end
        end)
    end

    local function handleMessage(raw)
        local ok, event = pcall(httpService.JSONDecode, httpService, raw)
        if not ok or type(event) ~= 'table' or event.event ~= 'message' then
            return
        end

        local ok2, data = pcall(httpService.JSONDecode, httpService, event.message)
        if not ok2 or type(data) ~= 'table' then
            return
        end

        if data.from == player.Name then
            return
        end

        local handler = handlers[data.type]
        if handler then
            task.spawn(handler, data.from, data.payload)
        end
    end

    local function startWebSocket()
        if not (WebSocket and WebSocket.connect) then
            return false
        end

        local ok, socket = pcall(WebSocket.connect, 'wss://ntfy.sh/' .. topic .. '/ws')
        if not ok or not socket then
            return false
        end

        socket.OnMessage:Connect(handleMessage)
        clean(function()
            pcall(function() socket:Close() end)
        end)
        return true
    end

    local function startPolling()
        if not requestFn then
            return
        end

        task.spawn(function()
            local since = tostring(os.time())

            while running do
                local ok, response = pcall(requestFn, {
                    Url = baseUrl .. '/json?poll=1&since=' .. since,
                    Method = 'GET',
                })

                if ok and response and response.Body then
                    for line in string.gmatch(response.Body, '[^\n]+') do
                        local ok2, event = pcall(httpService.JSONDecode, httpService, line)
                        if ok2 and type(event) == 'table' and event.id then
                            since = event.id
                            handleMessage(line)
                        end
                    end
                end

                task.wait(2)
            end
        end)
    end

    if not startWebSocket() then
        startPolling()
    end
end

return Net
