-- Settings: from the title screen (Settings), and in play (Esc, or the Settings
-- button in the top-right corner). Its tabs:
--   Graphics  fullscreen, VSync (desktop), camera zoom, how dark nights and
--             dungeons get, screen shake, particles, wind, the minimap, and a
--             frame counter
--   Sound     master, music and sound effects volume
--   Controls  two keys for each action (src/utilities/controls.lua), and back
--             to the defaults
--   Wallet    (in the browser) connect, switch to Hemi, disconnect, and how
--             the journey is saved
-- In play on desktop its foot has Quit beside Resume.
-- A change is kept as soon as it's made (src/utilities/settings.lua). In play
-- the world waits while it's open. Up / Down choose, Left / Right change, Enter
-- picks, Tab (or a click) changes tab, Esc goes back.

local webBridge = require("src/utilities/webBridge")

local ORANGE, GOLD, CREAM, MUTED = uiKit.ORANGE, uiKit.GOLD, uiKit.CREAM, uiKit.MUTED
local setColor, panel, tag = uiKit.setColor, uiKit.panel, uiKit.tag
local GREEN, AMBER, RED = { 0.45, 0.95, 0.55 }, { 1, 0.78, 0.35 }, { 1, 0.55, 0.45 }

settingsMenu = { active = false, tab = 1, row = 1, slot = 1, scroll = 0, t = 0, hits = {} }

local PW, PH = 204, 126 -- the panel, in the game's scale units
local ROW = 8           -- a row's height (and 1 between rows)

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end

function settingsMenu:tabs()
    local list = { { id = "graphics", name = "Graphics" }, { id = "sound", name = "Sound" }, { id = "controls", name = "Controls" } }
    if webBridge.isAvailable() then table.insert(list, { id = "wallet", name = "Wallet" }) end
    return list
end

-- context: "title" or "game"
function settingsMenu:open(context)
    if self.active then return end
    self.active = true
    self.context = context or "game"
    self.tab = clamp(self.tab, 1, #self:tabs())
    self.row, self.slot, self.scroll, self.follow = 0, 1, 0, true
    self.capture, self.note = nil, nil
    self:move(1, true)
    dj.play(sounds.ui.menuOpen, "static", "effect")
    if webBridge.isAvailable() then onchain:start("status") end
end

function settingsMenu:close()
    if not self.active then return end
    self.active = false
    self.capture = nil
    dj.play(sounds.ui.menuClose, "static", "effect")
end

-- a line under the rows for a few seconds
function settingsMenu:say(text, color)
    self.note = { text = text, color = color or MUTED, time = 3 }
end

----------------------------------------------------------------------- the rows

-- a row: kind ("toggle", "slider", "choice", "button", "bind" or "text"), its
-- label, its value, and what changing it does
-- a setting chosen from a few (settings.CHOICES): Left / Right go round them
local function choice(key, label)
    return { kind = "choice", label = label, value = settings:choiceName(key), change = function(dir) settings:cycle(key, dir) end }
end

local function toggle(key, label, extra)
    local row = { kind = "toggle", label = label, value = settings.values[key] == true,
        change = function() settings:set(key, not settings.values[key]) end }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

function settingsMenu:graphicsRows()
    local rows = {}
    local desktop = love.system.getOS() ~= "Web"
    local fs = settings:fullscreenState()
    if fs then
        table.insert(rows, { kind = "toggle", label = "Fullscreen", value = fs == "on", key = desktop and "F11" or nil,
            change = function() toggleFullscreen(); settings:askFullscreenSoon() end })
    end
    if desktop then table.insert(rows, toggle("vsync", "VSync (no tearing)")) end
    table.insert(rows, choice("zoom", "Camera zoom"))
    table.insert(rows, choice("darkness", "Night and dungeon darkness"))
    table.insert(rows, choice("shake", "Screen shake"))
    table.insert(rows, choice("particles", "Particles"))
    table.insert(rows, toggle("wind", "Wind and leaves"))
    table.insert(rows, toggle("minimap", "Minimap", { key = controls:label("minimap"), change = function() settings:toggleMinimap() end }))
    table.insert(rows, toggle("fps", "Show FPS"))
    return rows
end

function settingsMenu:soundRows()
    local rows = {}
    for _, s in ipairs({ { "master", "Master volume" }, { "music", "Music" }, { "effects", "Sound effects" } }) do
        table.insert(rows, { kind = "slider", label = s[2], value = settings.values[s[1]],
            change = function(v) settings:set(s[1], clamp(math.floor(v * 10 + 0.5) / 10, 0, 1)) end })
    end
    return rows
end

function settingsMenu:controlRows()
    local rows = { { kind = "text", text = "The mouse aims, and uses the left and right click items (choose them in the item menu).", color = MUTED } }
    for _, a in ipairs(controls.ACTIONS) do
        table.insert(rows, { kind = "bind", label = a.name, id = a.id })
    end
    table.insert(rows, { kind = "button", label = "Reset all keys to the defaults", action = function()
        controls:reset()
        settings:save()
        self:say("Every key is back to its default")
    end })
    table.insert(rows, { kind = "text", text = "Esc (Settings), F3 (developer) and F11 (fullscreen) stay as they are.", color = MUTED })
    return rows
end

local function shortAddress(address)
    if #address < 12 then return address end
    return address:sub(1, 6) .. "..." .. address:sub(-4)
end

function settingsMenu:walletRows()
    local r = onchain.remote
    local rows = {}
    local function text(t, color) table.insert(rows, { kind = "text", text = t, color = color or CREAM }) end
    local connected = onchain:connected()
    local target = (r.chain or "") ~= "" and r.chain or "Hemi"
    if connected then
        text("Connected:  " .. shortAddress(r.address), GREEN)
        local walletChain = (r.walletChain or "") ~= "" and r.walletChain or target
        if r.rightChain == "0" then
            text("Your wallet is on " .. walletChain .. "; the game uses " .. target .. ".", AMBER)
        else
            text("On " .. walletChain, GREEN)
        end
    elseif r.wallet == "0" then
        text("No browser wallet found. Install MetaMask or another EVM wallet, then reload the page.", RED)
    else
        text("Not connected")
    end
    if r.state == "working" then
        text(((r.step or "") ~= "" and r.step or "Working") .. string.rep(".", math.floor(self.t * 3) % 4), AMBER)
    elseif r.state == "error" and (r.error or "") ~= "" then
        text(r.error, RED)
    end
    if not connected then
        table.insert(rows, { kind = "button", label = "Connect wallet", action = function() hemiExchange:connect() end })
    else
        if r.rightChain == "0" then
            table.insert(rows, { kind = "button", label = "Switch to " .. target, action = function() hemiExchange:switchNetwork() end })
        end
        table.insert(rows, { kind = "button", label = "Disconnect", action = function() hemiExchange:disconnect() end })
    end
    if r.saves == "1" then
        text(connected and "Checkpoints save your journey on-chain, as well as on this device."
            or "Connected, checkpoints save your journey on-chain too, and Continue can load it anywhere.", MUTED)
    elseif (r.saves or "") ~= "" then
        text("On-chain saves aren't available on this server.", MUTED)
    end
    if self.context == "game" then
        text("Gold: " .. data.money .. "  -  exchange it for HEMI with Nova at the Hemi Exchange stall in Willowbrook.", GOLD)
    end
    return rows
end

function settingsMenu:rows()
    local id = self:tabs()[self.tab].id
    if id == "controls" then return self:controlRows() end
    if id == "wallet" then return self:walletRows() end
    if id == "sound" then return self:soundRows() end
    return self:graphicsRows()
end

----------------------------------------------------------------------- choosing

local function selectable(row) return row and row.kind ~= "text" end

-- to the next row that can be chosen, up (-1) or down (1) (quiet: no click)
function settingsMenu:move(dir, quiet)
    local rows = self:rows()
    local i = self.row
    for _ = 1, #rows do
        i = i + dir
        if i < 1 then i = #rows elseif i > #rows then i = 1 end
        if selectable(rows[i]) then
            if i ~= self.row and self.row > 0 and not quiet then dj.play(sounds.ui.click, "static", "effect", 0.5) end
            self.row = i
            self.follow = true
            return
        end
    end
end

function settingsMenu:setTab(i)
    local n = #self:tabs()
    i = (i - 1) % n + 1
    if i == self.tab then return end
    self.tab = i
    self.row, self.slot, self.scroll, self.capture = 0, 1, 0, nil
    self:move(1, true)
    dj.play(sounds.ui.click, "static", "effect", 0.7)
end

-- Left (-1) / Right (1) on the chosen row
function settingsMenu:change(dir)
    local row = self:rows()[self.row]
    if not selectable(row) then return end
    if row.kind == "toggle" then
        row.change()
    elseif row.kind == "slider" then
        row.change(row.value + dir * 0.1)
    elseif row.kind == "choice" then
        row.change(dir)
    elseif row.kind == "bind" then
        self.slot = clamp(self.slot + dir, 1, controls.SLOTS)
    else
        return
    end
    dj.play(sounds.ui.click, "static", "effect", 0.6)
end

-- Enter on the chosen row
function settingsMenu:activate()
    local row = self:rows()[self.row]
    if not selectable(row) then return end
    if row.kind == "toggle" or row.kind == "choice" then
        self:change(1)
    elseif row.kind == "button" then
        dj.play(sounds.ui.select, "static", "effect")
        row.action()
    elseif row.kind == "bind" then
        self.capture = { id = row.id, slot = self.slot }
        dj.play(sounds.ui.click, "static", "effect")
    end
end

-- choosing a key: the next key pressed goes on the action
function settingsMenu:captureKey(key)
    local id, slot = self.capture.id, self.capture.slot
    local name = controls.byId[id].name
    if key == "escape" then
        self.capture = nil
        self:say(name .. ": unchanged")
    elseif key == "backspace" or key == "delete" then
        controls:clear(id, slot)
        settings:save()
        self.capture = nil
        self:say(name .. ": key " .. slot .. " cleared")
    elseif not controls:canBind(key) then
        self:say(controls.keyName(key) .. " is kept by the game: choose another key", RED)
    else
        local taken = controls:bind(id, slot, key)
        settings:save()
        self.capture = nil
        dj.play(sounds.ui.select, "static", "effect")
        if #taken > 0 then
            self:say(controls.keyName(key) .. " is now " .. name .. " (taken from " .. table.concat(taken, ", ") .. ")", AMBER)
        else
            self:say(name .. ": " .. controls.keyName(key), GREEN)
        end
    end
end

function settingsMenu:keypressed(key)
    if self.capture then return self:captureKey(key) end
    if key == "escape" then
        return self:close()
    end
    if key == "tab" then
        self:setTab(self.tab + ((love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) and -1 or 1))
    elseif key == "pageup" then
        self:setTab(self.tab - 1)
    elseif key == "pagedown" then
        self:setTab(self.tab + 1)
    elseif key == "up" or key == "w" then
        self:move(-1)
    elseif key == "down" or key == "s" then
        self:move(1)
    elseif key == "left" or key == "a" then
        self:change(-1)
    elseif key == "right" or key == "d" then
        self:change(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        self:activate()
    end
end

----------------------------------------------------------------------- the mouse

local function inside(h, x, y)
    return x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h
end

-- (the parts of a row are drawn after the row, so they're found first)
function settingsMenu:hitAt(x, y)
    for i = #self.hits, 1, -1 do
        if inside(self.hits[i], x, y) then return self.hits[i] end
    end
end

function settingsMenu:mousepressed(x, y, button)
    if button ~= 1 then return end
    local hit = self:hitAt(x, y)
    if self.capture then
        self.capture = nil -- (a click anywhere stops choosing a key)
        self:say("Unchanged")
        if not hit or hit.part ~= "slot" then return end
    end
    if not hit then return end
    if hit.tab then return self:setTab(hit.tab) end
    if hit.close then return self:close() end
    if hit.quit then return love.event.quit() end
    local row = self:rows()[hit.row]
    if not selectable(row) then return end
    self.row, self.follow = hit.row, false
    if hit.part == "slot" then
        self.slot = hit.slot
        self:activate()
    elseif hit.part == "dec" or hit.part == "inc" then
        self:change(hit.part == "dec" and -1 or 1)
    elseif hit.part == "segment" then
        row.change(hit.value)
        dj.play(sounds.ui.click, "static", "effect", 0.6)
    elseif row.kind ~= "slider" and row.kind ~= "bind" then
        self:activate()
    end
end

function settingsMenu:mousemoved(x, y)
    if self.capture then return end
    local hit = self:hitAt(x, y)
    if hit and hit.row and hit.row ~= self.row and selectable(self:rows()[hit.row]) then
        self.row, self.follow = hit.row, false
        dj.play(sounds.ui.click, "static", "effect", 0.3)
    end
end

function settingsMenu:wheelmoved(dy)
    self.scroll = self.scroll - dy * (ROW + 1) * scale * 1.5
    self.follow = false
end

function settingsMenu:update(dt)
    self.t = self.t + dt
    if self.note then
        self.note.time = self.note.time - dt
        if self.note.time <= 0 then self.note = nil end
    end
    settings:pollFullscreen(dt)
    -- the rows can change under the choice (the wallet connects, a button
    -- goes): the next one down that can be chosen
    local rows = self:rows()
    if not selectable(rows[self.row]) then
        self.row = clamp(self.row - 1, 0, #rows)
        self:move(1, true)
    end
end

----------------------------------------------------------------------- drawing

function settingsMenu:layout()
    local w, h = love.graphics.getDimensions()
    local pw, ph = math.min(math.floor(PW * scale), w - math.floor(8 * scale)), math.min(math.floor(PH * scale), h - math.floor(6 * scale))
    return math.floor((w - pw) / 2), math.floor((h - ph) / 2), pw, ph
end

-- how tall a row is drawn
local function rowHeight(row, width)
    if row.kind == "text" then
        local _, lines = fonts.menuSmall:getWrap(row.text, width)
        return #lines * fonts.menuSmall:getHeight() + math.floor(1.5 * scale)
    end
    return math.floor(ROW * scale)
end

function settingsMenu:drawSlider(row, i, right, cy, selected)
    local segW, segH, gap = math.floor(3.2 * scale), math.floor(3.6 * scale), math.floor(0.8 * scale)
    local f = fonts.menuSmall
    love.graphics.setFont(f)
    local valueW = f:getWidth("100%")
    local text = math.floor(row.value * 100 + 0.5) .. "%"
    setColor(CREAM, selected and 1 or 0.75)
    love.graphics.print(text, right - f:getWidth(text), cy - f:getHeight() / 2)
    local arrowW = f:getWidth(">") + math.floor(2 * scale)
    local barRight = right - valueW - math.floor(3 * scale) - arrowW
    local barW = 10 * segW + 9 * gap
    local barX = barRight - barW
    -- the arrows
    setColor(selected and ORANGE or MUTED, selected and 1 or 0.5)
    love.graphics.print("<", barX - arrowW + math.floor(0.5 * scale), cy - f:getHeight() / 2)
    love.graphics.print(">", barRight + math.floor(1.5 * scale), cy - f:getHeight() / 2)
    table.insert(self.hits, { x = barX - arrowW, y = cy - segH, w = arrowW, h = segH * 2, row = i, part = "dec" })
    table.insert(self.hits, { x = barRight, y = cy - segH, w = arrowW, h = segH * 2, row = i, part = "inc" })
    -- ten steps, lit up to the value
    local lit = math.floor(row.value * 10 + 0.5)
    for s = 1, 10 do
        local sx = barX + (s - 1) * (segW + gap)
        if s <= lit then
            love.graphics.setColor(ORANGE[1], ORANGE[2] + 0.04 * s, ORANGE[3] + 0.02 * s, selected and 1 or 0.7)
        else
            love.graphics.setColor(0.25, 0.2, 0.2, 0.9)
        end
        love.graphics.rectangle("fill", sx, cy - segH / 2, segW, segH)
        table.insert(self.hits, { x = sx - gap / 2, y = cy - segH, w = segW + gap, h = segH * 2, row = i, part = "segment", value = s / 10 })
    end
end

function settingsMenu:drawBind(row, i, right, cy, selected, rh)
    local f = fonts.menuSmall
    local boxW, boxH, gap = math.floor(32 * scale), rh - math.floor(1.6 * scale), math.floor(3 * scale)
    for s = controls.SLOTS, 1, -1 do
        local bx = right - (controls.SLOTS - s + 1) * boxW - (controls.SLOTS - s) * gap
        local by = cy - boxH / 2
        local chosen = selected and self.slot == s
        local capturing = self.capture and self.capture.id == row.id and self.capture.slot == s
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], capturing and 0.4 or (chosen and 0.22 or 0))
        panel("fill", bx, by, boxW, boxH, math.floor(scale))
        love.graphics.setColor(0, 0, 0, chosen and 0 or 0.35)
        panel("fill", bx, by, boxW, boxH, math.floor(scale))
        love.graphics.setLineWidth(math.max(1, math.floor(scale * 0.35)))
        setColor(chosen and ORANGE or { 0.55, 0.45, 0.38 }, chosen and 1 or 0.7)
        panel("line", bx, by, boxW, boxH, math.floor(scale))
        local key = controls:key(row.id, s)
        local text, color, alpha = key and controls.keyName(key) or "-", CREAM, key and 1 or 0.4
        if capturing then
            text, color, alpha = "Press a key", AMBER, 0.55 + 0.45 * math.abs(math.sin(self.t * 4))
        end
        love.graphics.setFont(f)
        setColor(color, alpha)
        love.graphics.printf(text, bx, cy - f:getHeight() / 2, boxW, "center")
        table.insert(self.hits, { x = bx, y = by, w = boxW, h = boxH, row = i, part = "slot", slot = s })
    end
end

function settingsMenu:drawRow(row, i, x, y, w, rh)
    local selected = i == self.row and selectable(row)
    local cy = y + rh / 2
    if row.kind == "text" then
        love.graphics.setFont(fonts.menuSmall)
        setColor(row.color, 1)
        love.graphics.printf(row.text, x + math.floor(3 * scale), y + math.floor(0.5 * scale), w - math.floor(6 * scale), "left")
        return
    end
    table.insert(self.hits, { x = x, y = y, w = w, h = rh, row = i })
    local c = math.floor(scale)
    if selected then
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.14)
        panel("fill", x, y, w, rh, c)
        love.graphics.setLineWidth(math.max(1, math.floor(scale * 0.35)))
        setColor(row.danger and RED or ORANGE, 0.85)
        panel("line", x, y, w, rh, c)
    else
        love.graphics.setColor(1, 1, 1, 0.03)
        panel("fill", x, y, w, rh, c)
    end
    local pad, right = math.floor(4 * scale), x + w - math.floor(4 * scale)
    local f = fonts.menu
    if row.kind == "button" then
        love.graphics.setFont(f)
        setColor(row.danger and RED or CREAM, selected and 1 or 0.78)
        love.graphics.printf(row.label, x, cy - f:getHeight() / 2, w, "center")
        return
    end
    love.graphics.setFont(f)
    setColor(CREAM, selected and 1 or 0.8)
    love.graphics.print(row.label, x + pad, cy - f:getHeight() / 2)
    if row.kind == "toggle" then
        local left = tag(row.value and "ON" or "OFF", right, cy, row.value and { 0.28, 0.62, 0.3 } or { 0.3, 0.26, 0.26 }, CREAM)
        if row.key then tag(row.key, left - math.floor(2 * scale), cy, { 1, 1, 1, 0.08 }, MUTED) end
    elseif row.kind == "slider" then
        self:drawSlider(row, i, right, cy, selected)
    elseif row.kind == "choice" then
        local sf = fonts.menuSmall
        love.graphics.setFont(sf)
        local boxW = math.floor(30 * scale)
        local arrowW = sf:getWidth("<") + math.floor(2 * scale)
        setColor(selected and ORANGE or MUTED, selected and 1 or 0.5)
        love.graphics.print("<", right - boxW, cy - sf:getHeight() / 2)
        love.graphics.print(">", right - sf:getWidth(">"), cy - sf:getHeight() / 2)
        setColor(CREAM, selected and 1 or 0.8)
        love.graphics.printf(row.value, right - boxW, cy - sf:getHeight() / 2, boxW, "center")
        table.insert(self.hits, { x = right - boxW - math.floor(scale), y = y, w = arrowW + math.floor(2 * scale), h = rh, row = i, part = "dec" })
        table.insert(self.hits, { x = right - arrowW, y = y, w = arrowW + math.floor(scale), h = rh, row = i, part = "inc" })
    elseif row.kind == "bind" then
        self:drawBind(row, i, right, cy, selected, rh)
    end
end

function settingsMenu:draw()
    if not self.active then return end
    local w, h = love.graphics.getDimensions()
    self.hits = {}
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local x, y, pw, ph = self:layout()
    local c = math.floor(2 * scale)
    uiKit.glow(w / 2, h / 2, pw * 0.62, ph * 0.66, ORANGE, 0.1, 10)
    love.graphics.setColor(0.06, 0.04, 0.05, 0.97)
    panel("fill", x, y, pw, ph, c)
    love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.45)))
    setColor(ORANGE, 1)
    panel("line", x, y, pw, ph, c)

    -- the title, and the tabs
    love.graphics.setFont(fonts.menuBig)
    setColor(CREAM, 1)
    love.graphics.printf("Settings", x, y + math.floor(2.5 * scale), pw, "center")
    local tabs = self:tabs()
    local tw, th, gap = math.floor(40 * scale), math.floor(8 * scale), math.floor(3 * scale)
    local tx = math.floor(x + (pw - (#tabs * tw + (#tabs - 1) * gap)) / 2)
    local ty = y + math.floor(4 * scale) + fonts.menuBig:getHeight()
    for i, t in ipairs(tabs) do
        local chosen = i == self.tab
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], chosen and 0.9 or 0.12)
        panel("fill", tx, ty, tw, th, math.floor(scale))
        love.graphics.setLineWidth(math.max(1, math.floor(scale * 0.35)))
        setColor(ORANGE, chosen and 1 or 0.45)
        panel("line", tx, ty, tw, th, math.floor(scale))
        love.graphics.setFont(fonts.menu)
        if chosen then love.graphics.setColor(0.14, 0.05, 0.02, 1) else setColor(CREAM, 0.75) end
        love.graphics.printf(t.name, tx, ty + (th - fonts.menu:getHeight()) / 2, tw, "center")
        table.insert(self.hits, { x = tx, y = ty, w = tw, h = th, tab = i })
        tx = tx + tw + gap
    end

    -- the rows, scrolled to keep the chosen one in sight
    local footH = math.floor(11 * scale)
    local cx, cw = x + math.floor(7 * scale), pw - math.floor(14 * scale)
    local cy = ty + th + math.floor(4 * scale)
    local ch = y + ph - footH - cy
    local rows = self:rows()
    local tops, total = {}, 0
    for i, row in ipairs(rows) do
        tops[i] = total
        total = total + rowHeight(row, cw - math.floor(6 * scale)) + math.floor(scale)
    end
    if self.follow and tops[self.row] then
        local top, bottom = tops[self.row], tops[self.row] + rowHeight(rows[self.row], cw)
        if top < self.scroll then self.scroll = top end
        if bottom > self.scroll + ch then self.scroll = bottom - ch end
    end
    self.scroll = clamp(self.scroll, 0, math.max(0, total - ch))
    love.graphics.setScissor(cx - math.floor(scale), cy, cw + math.floor(2 * scale), ch)
    local first = #self.hits
    for i, row in ipairs(rows) do
        local ry = cy + tops[i] - self.scroll
        local rh = rowHeight(row, cw - math.floor(6 * scale))
        if ry + rh > cy and ry < cy + ch then self:drawRow(row, i, cx, ry, cw, rh) end
    end
    love.graphics.setScissor()
    -- (what's scrolled out of sight can't be clicked)
    for i = #self.hits, first + 1, -1 do
        local hit = self.hits[i]
        if hit.y + hit.h / 2 < cy or hit.y + hit.h / 2 > cy + ch then table.remove(self.hits, i) end
    end
    if total > ch then
        local barH = math.max(math.floor(6 * scale), ch * ch / total)
        local barY = cy + (ch - barH) * (self.scroll / (total - ch))
        love.graphics.setColor(1, 1, 1, 0.08)
        love.graphics.rectangle("fill", x + pw - math.floor(4.5 * scale), cy, math.floor(1.2 * scale), ch)
        setColor(ORANGE, 0.7)
        love.graphics.rectangle("fill", x + pw - math.floor(4.5 * scale), barY, math.floor(1.2 * scale), barH)
    end

    -- the foot: what the keys do (or what just happened), and Back / Resume
    local fy = y + ph - footH
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.rectangle("fill", x + c, fy, pw - 2 * c, math.max(1, math.floor(scale * 0.3)))
    local f = fonts.menuSmall
    love.graphics.setFont(f)
    local hint, color = nil, MUTED
    if self.capture then
        hint, color = "Press a key for " .. controls.byId[self.capture.id].name .. "   \194\183   Esc: cancel   \194\183   Backspace: clear", AMBER
    elseif self.note then
        hint, color = self.note.text, self.note.color
    elseif self:tabs()[self.tab].id == "controls" then
        hint = "Enter or click: set a key  \194\183  Left / Right: 1st or 2nd key  \194\183  Tab: next tab"
    else
        hint = "Up / Down: choose  \194\183  Left / Right: change  \194\183  Enter: select  \194\183  Tab: next tab"
    end
    local backText = self.context == "game" and "Resume" or "Back"
    local backW = f:getWidth(backText) + math.floor(6 * scale)
    local bx, by, bh = x + pw - math.floor(6 * scale) - backW, fy + math.floor(2.2 * scale), footH - math.floor(4.4 * scale)
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
    panel("fill", bx, by, backW, bh, math.floor(scale))
    setColor(ORANGE, 1)
    panel("line", bx, by, backW, bh, math.floor(scale))
    setColor(CREAM, 1)
    love.graphics.printf(backText, bx, by + (bh - f:getHeight()) / 2, backW, "center")
    local keyLeft = tag("Esc", bx - math.floor(2 * scale), by + bh / 2, { 1, 1, 1, 0.08 }, MUTED)
    table.insert(self.hits, { x = bx, y = by, w = backW, h = bh, close = true })
    if self.context == "game" and love.system.getOS() ~= "Web" then
        local quitW = f:getWidth("Quit game") + math.floor(6 * scale)
        local qx = keyLeft - math.floor(5 * scale) - quitW
        love.graphics.setColor(RED[1], RED[2], RED[3], 0.12)
        panel("fill", qx, by, quitW, bh, math.floor(scale))
        setColor(RED, 0.9)
        panel("line", qx, by, quitW, bh, math.floor(scale))
        love.graphics.printf("Quit game", qx, by + (bh - f:getHeight()) / 2, quitW, "center")
        table.insert(self.hits, { x = qx, y = by, w = quitW, h = bh, quit = true })
        keyLeft = qx
    end
    love.graphics.setFont(f)
    setColor(color, 1)
    love.graphics.printf(hint, x + math.floor(7 * scale), fy + (footH - f:getHeight()) / 2, keyLeft - x - math.floor(10 * scale), "left")

    love.graphics.setLineWidth(1)
    setWhite()
end
