repeat task.wait() until game:IsLoaded()

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

local playersService = game:GetService('Players')
local httpService = game:GetService('HttpService')

local lplr = playersService.LocalPlayer

local net = {}

do
    local topic = ...
    local base = 'https://ntfy.sh/' .. topic

    local requestFn = request or http_request or (syn and syn.request) or (http and http.request)
    local running = true
    local handlers = {}

    clean(function()
        running = false
    end)

    function net.on(kind, fn)
        handlers[kind] = fn
    end

    net.recieve = net.on -- you can't spell
    net.receive = net.on

    function net.send(kind, payload)
        if not requestFn then
            print('ntfy: no request function')
            return
        end
        task.spawn(function()
            local ok, res = pcall(requestFn, {
                Url = base,
                Method = 'POST',
                Body = httpService:JSONEncode({
                    type = kind,
                    from = lplr.Name,
                    payload = payload
                })
            })
            print('ntfy send', kind, ok, ok and res and (res.StatusCode or res.Status))
        end)
    end

    local function handle(raw)
        local ok, event = pcall(function()
            return httpService:JSONDecode(raw)
        end)
        if not ok or type(event) ~= 'table' or event.event ~= 'message' then return end

        local ok2, data = pcall(function()
            return httpService:JSONDecode(event.message)
        end)
        if not ok2 or type(data) ~= 'table' then return end
        if data.from == lplr.Name then return end

        local handler = handlers[data.type]
        if handler then
            task.spawn(handler, data.from, data.payload)
        end
    end

    local connected = false

    if WebSocket and WebSocket.connect then
        local ok, socket = pcall(WebSocket.connect, 'wss://ntfy.sh/' .. topic .. '/ws')
        if ok and socket then
            connected = true
            socket.OnMessage:Connect(handle)
            clean(function()
                pcall(function() socket:Close() end)
            end)
        end
    end

    print(connected and 'net: websocket' or 'net: polling')

    if not connected and requestFn then
        task.spawn(function()
            local since = tostring(os.time())
            while running do
                local ok, res = pcall(requestFn, {
                    Url = base .. '/json?poll=1&since=' .. since,
                    Method = 'GET'
                })
                if ok and res and res.Body then
                    for line in string.gmatch(res.Body, '[^\n]+') do
                        local ok2, event = pcall(function()
                            return httpService:JSONDecode(line)
                        end)
                        if ok2 and type(event) == 'table' and event.id then
                            since = event.id
                            handle(line)
                        end
                    end
                end
                task.wait(2)
            end
        end)
    end
end

return net
