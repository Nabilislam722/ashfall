-- Lua side of the Lua <-> JavaScript bridge (browser builds only).
--
-- love.js evaluates "javascript:" URLs passed to love.system.openURL and hands
-- the result back on stdin (see web/player.js), so a call is: open the URL,
-- then read the answer with io.read. Wallet work is asynchronous, so the page
-- (web/bridge.js) exposes start(action, query) and poll(); the game starts an
-- action and polls the state every few frames.

local webBridge = {}

local BRIDGE = "window.ashfallBridge"

function webBridge.isAvailable()
    return love.system.getOS() == "Web"
end

-- true when the page has its own ☰ menu (web/menu.js). An older or custom
-- index.html may not, and then the game draws its own button. Checked once.
function webBridge.hasPageMenu()
    if not webBridge.isAvailable() then return false end
    if webBridge.pageMenu == nil then
        webBridge.pageMenu = webBridge.eval("window.ashfallMenu ? '1' : '0'") == "1"
    end
    return webBridge.pageMenu
end

-- runs a JavaScript expression in the page and returns its value as a string
function webBridge.eval(js)
    love.system.openURL("javascript:" .. js)
    local lines = {}
    while true do
        local line = io.read()
        if not line then break end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end

local function encode(value)
    return (tostring(value):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function decode(value)
    value = value:gsub("%+", " ")
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function webBridge.encodeQuery(params)
    local keys = {}
    for key in pairs(params) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode(key) .. "=" .. encode(params[key])
    end
    return table.concat(parts, "&")
end

function webBridge.decodeQuery(text)
    local result = {}
    for pair in (text or ""):gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=?(.*)$")
        if key and key ~= "" then
            result[decode(key)] = decode(value)
        end
    end
    return result
end

-- starts an asynchronous action in the page; returns "ok", "busy", "unknown",
-- "missing" (bridge.js not loaded) or "unavailable" (not a browser build)
function webBridge.start(action, params)
    if not webBridge.isAvailable() then return "unavailable" end
    local js = string.format("%s ? %s.start('%s', '%s') : 'missing'",
        BRIDGE, BRIDGE, encode(action), webBridge.encodeQuery(params or {}))
    return webBridge.eval(js)
end

-- returns the page's current state as a table of strings
function webBridge.poll()
    if not webBridge.isAvailable() then return { state = "unavailable" } end
    local js = string.format("%s ? %s.poll() : 'state=error&error=The+web+bridge+did+not+load.'", BRIDGE, BRIDGE)
    return webBridge.decodeQuery(webBridge.eval(js))
end

-- kept for the original interface
function webBridge.request(action, payload)
    local result = webBridge.start(action, payload)
    return result == "ok", result
end

return webBridge
