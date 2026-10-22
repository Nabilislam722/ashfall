-- The ☰ button in the top-right corner and its dropdown (wallet connection).
-- Click it or press M. Wallet state is shared with the Hemi Exchange.
-- In the browser the menu lives in the web page instead (web/menu.js), so the
-- in-game button is hidden there and M opens the page menu. If the page has no
-- menu (an old index.html), the in-game button is shown in the browser too.

local webBridge = require("src/utilities/webBridge")

topMenu = {}
topMenu.open = false
topMenu.hover = false
topMenu.buttons = {}

local ORANGE = {1, 0.42, 0.1}

local function buttonRect()
    local hs = hudScale()
    local size = 13 * hs
    return love.graphics.getWidth() - size - 6, 6, size, size
end

local function inside(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function shortAddress(address)
    if not address or #address < 12 then return address or "" end
    return address:sub(1, 6) .. "..." .. address:sub(-4)
end

function topMenu:toggle()
    if webBridge.hasPageMenu() then
        webBridge.eval("window.ashfallBridge ? ashfallBridge.toggleMenu() : 'missing'")
        return
    end
    if self.open then
        self:close()
    else
        self.open = true
        dj.play(sounds.ui.menuOpen, "static", "effect")
        if webBridge.isAvailable() then
            local remote = hemiExchange.remote
            if remote.state ~= "working" and (remote.configured or "") == "" then
                webBridge.start("status")
            end
            hemiExchange:poll()
        end
    end
end

function topMenu:close()
    if not self.open then return end
    self.open = false
    dj.play(sounds.ui.menuClose, "static", "effect")
end

function topMenu:connect()
    hemiExchange:connect()
end

-- true when the menu is usable (not hidden behind a window or cutscene)
function topMenu:visible()
    if webBridge.hasPageMenu() then return false end
    return gamestate == 1 and not pause.active and not dialogue.active and not shop.active
        and not hemiExchange.active and not manaWell.active and not cutscene.active and not respawn.pending
end

-- M works during play: in-game menu on desktop, the page menu in the browser
function topMenu:canToggle()
    return self:visible() or (webBridge.hasPageMenu() and gamestate == 1)
end

-- returns true when the click was for the menu (so it doesn't swing the sword)
function topMenu:mousepressed(x, y, button)
    if not self:visible() then return false end
    if inside(x, y, buttonRect()) then
        if button == 1 then self:toggle() end
        return true
    end
    if not self.open then return false end
    for _, b in ipairs(self.buttons) do
        if b.enabled and inside(x, y, b.x, b.y, b.w, b.h) then
            if button == 1 then b.action(self) end
            return true
        end
    end
    -- clicking anywhere else just closes the menu
    self:close()
    return true
end

function topMenu:keypressed(key)
    if key == "escape" or key == "m" or key == "tab" then
        self:close()
    elseif key == "c" or key == "return" or key == "e" then
        self:connect()
    elseif key == "s" then
        hemiExchange:switchNetwork()
    elseif key == "d" then
        hemiExchange:disconnect()
    end
end

function topMenu:draw()
    if not self:visible() then return end
    local hs = hudScale()
    local bx, by, bw, bh = buttonRect()
    local mx, my = love.mouse.getPosition()
    local hover = inside(mx, my, bx, by, bw, bh)
    local remote = hemiExchange.remote
    local connected = (remote.address or "") ~= ""

    -- the ☰ button
    love.graphics.setColor(0, 0, 0, (hover or self.open) and 0.75 or 0.5)
    love.graphics.rectangle("fill", bx, by, bw, bh, hs * 1.5, hs * 1.5)
    if self.open then
        love.graphics.setLineWidth(math.max(2, math.floor(hs * 0.5)))
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        love.graphics.rectangle("line", bx, by, bw, bh, hs * 1.5, hs * 1.5)
    end
    love.graphics.setColor(1, 1, 1, 1)
    local lineW, lineH = bw * 0.56, math.max(2, math.floor(hs * 1.2))
    for i = -1, 1 do
        local ly = by + bh / 2 + i * bh * 0.22 - lineH / 2
        love.graphics.rectangle("fill", bx + (bw - lineW) / 2, ly, lineW, lineH, lineH / 2, lineH / 2)
    end
    if connected then
        -- green dot: wallet connected
        love.graphics.setColor(0.1, 0.1, 0.1, 1)
        love.graphics.circle("fill", bx + bw - hs * 1.6, by + hs * 1.6, hs * 1.6)
        love.graphics.setColor(0.35, 0.95, 0.45, 1)
        love.graphics.circle("fill", bx + bw - hs * 1.6, by + hs * 1.6, hs * 1.1)
    end

    self.buttons = {}
    if not self.open then
        setWhite()
        love.graphics.setLineWidth(1)
        return
    end

    -- dropdown
    local available = webBridge.isAvailable()
    local working = available and remote.state == "working"
    local pad = 3 * hs
    local w = 104 * hs
    local x = bx + bw - w
    local y = by + bh + 2 * hs
    local lines = {}

    local function add(text, font, color)
        table.insert(lines, { text = text, font = font, color = color })
    end

    add("WALLET", fonts.menuSmall, {0.7, 0.66, 0.6})
    local actions = {}
    local target = (remote.chain or "") ~= "" and remote.chain or "Hemi"
    if not available then
        add("Wallet connect works in the browser version of the game.", fonts.menuSmall, {0.85, 0.82, 0.76})
    elseif connected then
        add(shortAddress(remote.address), fonts.menu, {0.97, 0.95, 0.9})
        local walletChain = (remote.walletChain or "") ~= "" and remote.walletChain or target
        if remote.rightChain == "0" then
            add("On " .. walletChain .. ", the exchange uses " .. target, fonts.menuSmall, {1, 0.72, 0.3})
            table.insert(actions, { label = "Switch to " .. target .. "  [S]", run = function() hemiExchange:switchNetwork() end })
        else
            add("On " .. walletChain, fonts.menuSmall, {0.45, 0.95, 0.55})
        end
        if working then
            add((remote.step ~= "" and remote.step or "Working") .. string.rep(".", math.floor(love.timer.getTime() * 3) % 4),
                fonts.menuSmall, {1, 0.85, 0.45})
        elseif remote.state == "error" and (remote.error or "") ~= "" then
            add(remote.error, fonts.menuSmall, {1, 0.55, 0.45})
        end
        table.insert(actions, { label = "Disconnect  [D]", run = function() hemiExchange:disconnect() end })
    elseif working then
        local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
        add((remote.step ~= "" and remote.step or "Connecting") .. dots, fonts.menuSmall, {1, 0.85, 0.45})
    else
        if remote.state == "error" and (remote.error or "") ~= "" then
            add(remote.error, fonts.menuSmall, {1, 0.55, 0.45})
        elseif remote.wallet == "0" then
            add("No browser wallet found. Install MetaMask or another EVM wallet.", fonts.menuSmall, {1, 0.55, 0.45})
        end
        table.insert(actions, { label = "Connect wallet  [C]", run = function() self:connect() end })
    end
    add("Gold: " .. data.money .. "  (exchange it for HEMI at Nova's stall)", fonts.menuSmall, {1, 0.75, 0.3})

    -- measure
    local textW = w - pad * 2
    local height = pad
    for _, l in ipairs(lines) do
        local _, wrapped = l.font:getWrap(l.text, textW)
        l.h = #wrapped * l.font:getHeight()
        height = height + l.h + hs
    end
    local actionH = fonts.menu:getHeight() + 2 * hs
    height = height + #actions * (actionH + hs)
    height = height + pad

    love.graphics.setColor(0.07, 0.05, 0.06, 0.95)
    love.graphics.rectangle("fill", x, y, w, height, hs * 1.5, hs * 1.5)
    love.graphics.setLineWidth(math.max(2, math.floor(hs * 0.5)))
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    love.graphics.rectangle("line", x, y, w, height, hs * 1.5, hs * 1.5)

    local cy = y + pad
    for i, l in ipairs(lines) do
        love.graphics.setFont(l.font)
        love.graphics.setColor(l.color[1], l.color[2], l.color[3], 1)
        love.graphics.printf(l.text, x + pad, cy, textW, "left")
        cy = cy + l.h + hs
        -- the wallet buttons go right after the status lines, before the gold
        if i == #lines - 1 then
            for _, action in ipairs(actions) do
                local button = { x = x + pad, y = cy, w = textW, h = actionH, enabled = not working, action = action.run }
                local over = inside(mx, my, button.x, button.y, button.w, button.h)
                love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], (over and not working) and 0.45 or 0.25)
                love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, hs, hs)
                love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
                love.graphics.rectangle("line", button.x, button.y, button.w, button.h, hs, hs)
                love.graphics.setFont(fonts.menu)
                love.graphics.setColor(1, 0.95, 0.88, working and 0.5 or 1)
                love.graphics.printf(action.label, button.x, button.y + hs, button.w, "center")
                table.insert(self.buttons, button)
                cy = cy + actionH + hs
            end
        end
    end

    love.graphics.setLineWidth(1)
    setWhite()
end
