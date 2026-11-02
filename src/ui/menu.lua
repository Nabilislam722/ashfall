-- Title screen: Continue (load the last save) or New Game, over Willowbrook at
-- dusk with embers rising, plus Settings (src/ui/settingsMenu.lua: fullscreen,
-- the sound, the keys, and in the browser the wallet).
--
-- Saves live on this device (save.json) and, in the browser with a wallet
-- connected, in the AshfallSaves contract. Continue picks the newer of the
-- two. New Game wipes both: the on-chain slot is cleared with a transaction
-- (newGame) before the journey starts over.

local webBridge = require("src/utilities/webBridge")

menu = {}
menu.selected = 1
menu.confirming = false
menu.walletPrompt = nil -- New Game in the browser with no wallet: { state = "ask" | "connecting" | "found", error }
menu.modalHover = nil   -- the popup's button under the mouse
menu.message = nil
menu.busy = nil        -- text shown while waiting for the wallet
menu.localSave = nil
menu.options = {}
menu.t = 0

local ORANGE, GOLD, CREAM, MUTED = uiKit.ORANGE, uiKit.GOLD, uiKit.CREAM, uiKit.MUTED
local setColor, glow, shade, diamond, panel, tag = uiKit.setColor, uiKit.glow, uiKit.shade, uiKit.diamond, uiKit.panel, uiKit.tag

-- the backdrop: Willowbrook baked whole (src/ui/intro.lua), the camera
-- drifting over it on a slow loop (map pixels), at dusk
local BACKDROP_MAP = "village"
local DRIFT = { x = 860, y = 520, rx = 380, ry = 200 }
local DRIFT_ZOOM = 0.55   -- times the game's scale (rounded to whole pixels)
local BACKDROP_FADE = 2.5 -- seconds to come up out of the dark once baked

local TITLE = "ASHFALL"
local SUBTITLE = "A L P H A    T E S T I N G"
local SHINE_EVERY = 7     -- a glint runs along the title this often (seconds)

local TIP_TIME = 6.5
local TIPS = {
    "Swing into a blow on its white glint to clash it",
    "Roll or Shadow Step right as a blow lands: a perfect dodge slows the attacker",
    "A cut on a slowed foe is a counter, and hits three times as hard",
    "Hold {fireball} to charge a Fireball",
    "Rest at a shrine ({interact}) to save your journey",
    "Esc opens Settings: the keys, the sound, and your wallet",
}


local function clamp01(v) return math.max(0, math.min(1, v)) end
local function smooth(t) t = clamp01(t); return t * t * (3 - 2 * t) end


function menu:open()
    self.selected = 1
    self.confirming = false
    self.walletPrompt = nil
    self.message, self.info = nil, nil
    self.busy = nil
    self.localSave = saveState:readLocal()
    self.chainCache = nil
    if webBridge.isAvailable() then onchain:start("status") end
end

-- the on-chain save of the connected wallet, decoded (cached per text)
function menu:chainSave()
    local r = onchain.remote
    if not onchain:connected() or r.saveRead ~= "1" or (r.saveData or "") == "" then return nil end
    if not self.chainCache or self.chainCache.text ~= r.saveData then
        self.chainCache = { text = r.saveData, save = saveState:decode(r.saveData) }
    end
    return self.chainCache.save
end

-- the save Continue would load: { save, source = "chain" | "device", savedAt }
function menu:bestSave()
    local best = nil
    local chain = self:chainSave()
    if chain then
        best = { save = chain, source = "chain", savedAt = tonumber(onchain.remote.saveSavedAt) or 0 }
    end
    local device = self.localSave
    if device then
        local savedAt = tonumber(device.t) or 0
        if not best or savedAt > best.savedAt then
            best = { save = device, source = "device", savedAt = savedAt }
        end
    end
    return best
end

-- the wallet has an on-chain save, connected or not yet read
function menu:hasChainSave()
    return self:chainSave() ~= nil
end

local function ago(savedAt)
    local seconds = os.time() - (savedAt or 0)
    if savedAt == 0 or seconds < 0 then return "" end
    if seconds < 90 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 172800 then return math.floor(seconds / 3600) .. " h ago" end
    return math.floor(seconds / 86400) .. " days ago"
end

function menu:continueGame()
    local best = self:bestSave()
    if not best then return end
    local map, x, y = saveState:apply(best.save)
    if not map then
        self.message = "This save can't be loaded: " .. tostring(x)
        return
    end
    -- gold exchanged for HEMI after this save was written is already gone
    local currentRun = tonumber(onchain.remote.saveRunId)
    local saveRun = best.source == "chain" and currentRun or tonumber(best.save.run)
    local exchanged = tonumber(onchain.remote.exchangedRun)
    if exchanged and currentRun and saveRun == currentRun then
        local since = math.max(0, exchanged - data.goldExchanged)
        data.money = math.max(0, data.money - since)
        data.goldExchanged = exchanged
    end
    if not x or not y then x, y = 384, 310 end
    staff:refill()
    dj.play(sounds.ui.select, "static", "effect")
    self.startedFrom = best.source
    curtain:call(map, x, y, "fade")
end

function menu:startNewGame()
    saveState:deleteLocal()
    self.localSave = nil
    startFresh(1)
    dj.play(sounds.ui.select, "static", "effect")
    self.startedFrom = "new"
    self.warnNoWallet = webBridge.isAvailable() and not onchain:connected() -- (said once the journey is on screen)
    -- a new journey opens with the intro (src/ui/intro.lua); it ends on black,
    -- so the curtain starts closed
    intro:play(function()
        curtain:call(data.map, data.playerX, data.playerY, "fade")
        curtain.alpha = 1
    end)
end

-- a popup is up (the New Game question, or the wallet's): it has the keys and clicks
function menu:modal()
    return self.confirming or self.walletPrompt ~= nil
end

-- New Game in the browser with no wallet: offer one first. Connected, a
-- journey it (or this device) already holds is recommended to Continue; none,
-- and the new run starts on-chain. Play without is fine, with a warning (in the
-- popup, and once the journey starts).
function menu:askWallet()
    self.walletPrompt = { state = "ask" }
    self.modalHover = nil
    dj.play(sounds.ui.menuOpen, "static", "effect")
end

function menu:connectWallet()
    local prompt = self.walletPrompt
    prompt.state, prompt.error = "connecting", nil
    onchain:start("connect", nil, function(remote, ok)
        if self.walletPrompt == prompt and not ok then
            prompt.state = "ask"
            prompt.error = (remote.error or "") ~= "" and remote.error or "The wallet didn't connect."
        end
    end)
end

function menu:playWithoutWallet()
    self.walletPrompt = nil
    dj.play(sounds.ui.click, "static", "effect")
    self:offerNewGame()
end

-- connected (and its save read): a journey found is recommended to Continue;
-- none, and the new one starts (its run on-chain first)
function menu:walletConnected()
    if self:bestSave() then
        self.walletPrompt = { state = "found" }
        self.modalHover = nil
        dj.play(sounds.ui.select, "static", "effect")
        return
    end
    self.walletPrompt = nil
    self:newGame()
end

-- a journey found: Continue it (recommended), or start over (which asks first)
function menu:continueFound()
    self.walletPrompt = nil
    self:continueGame()
end

function menu:startOverFound()
    self.walletPrompt = nil
    self:offerNewGame()
end

-- New Game asked for: over a save it asks first, else straight on
function menu:offerNewGame()
    if self:bestSave() or self:hasChainSave() then
        self.confirming = true
        self.modalHover = nil
        dj.play(sounds.ui.click, "static", "effect")
    else
        self:newGame()
    end
end

-- with a wallet that saves on-chain, the new journey's run starts there first
-- (the newGame transaction, which also clears an old save); the journey starts
-- once it's done
function menu:newGame()
    if not onchain:canSave() then
        self:startNewGame()
        return
    end
    local clearing = self:hasChainSave()
    self.busy = clearing and "Clearing your on-chain save: confirm in your wallet"
        or "Starting your journey on-chain: confirm in your wallet (tiny gas fee)"
    self.message = nil
    onchain:start("newgame", nil, function(remote, ok)
        self.busy = nil
        if ok then
            self.chainCache = nil
            self:startNewGame()
        else
            self.message = (clearing and "Your on-chain save wasn't cleared" or "Your journey wasn't started on-chain")
                .. " (" .. (remote.error or "error") .. "). Choose New Game to try again."
        end
    end)
end

function menu:choices()
    local list = {}
    if self:bestSave() then table.insert(list, "continue") end
    table.insert(list, "new")
    table.insert(list, "settings")
    if not webBridge.isAvailable() then table.insert(list, "quit") end
    return list
end

function menu:choose(option)
    self.info = nil
    if option == "continue" then
        self:continueGame()
    elseif option == "new" then
        if webBridge.isAvailable() and not onchain:connected() then
            self:askWallet() -- (connect first: the wallet may hold a journey)
        else
            self:offerNewGame()
        end
    elseif option == "settings" then
        dj.play(sounds.ui.click, "static", "effect")
        settingsMenu:open("title")
    elseif option == "quit" then
        love.event.quit()
    end
end

function menu:keypressed(key)
    if gamestate ~= 0 or curtain.state ~= 0 then return end
    if self.busy then return end
    local choices = self:choices()
    if self.walletPrompt then
        local yes = key == "c" or key == "return" or key == "kpenter" or key == "e" or key == "space"
        if self.walletPrompt.state == "found" then
            if yes then
                self:continueFound()
            elseif key == "n" then
                self:startOverFound()
            elseif key == "escape" or key == "backspace" then
                self.walletPrompt = nil
            end
        elseif yes then
            if self.walletPrompt.state == "ask" then self:connectWallet() end
        elseif key == "n" or key == "escape" or key == "backspace" then
            self:playWithoutWallet()
        end
        return
    end
    if self.confirming then
        if key == "y" or key == "return" or key == "e" or key == "space" then
            self.confirming = false
            self:newGame()
        elseif key == "n" or key == "escape" or key == "backspace" then
            self.confirming = false
        end
        return
    end
    if key == "up" or key == "w" then
        self.selected = (self.selected - 2) % #choices + 1
        dj.play(sounds.ui.click, "static", "effect", 0.6)
    elseif key == "down" or key == "s" then
        self.selected = self.selected % #choices + 1
        dj.play(sounds.ui.click, "static", "effect", 0.6)
    elseif key == "return" or key == "space" or key == "e" or key == "kpenter" then
        self:choose(choices[math.min(self.selected, #choices)])
    elseif key == "c" and webBridge.isAvailable() and not onchain:connected() then
        onchain:start("connect")
    end
end

-- (while a popup is up, only its buttons answer: the choices lie under them)
function menu:hit(b, x, y)
    return x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
        and (not self:modal() or b.modal == true)
end

function menu:mousepressed(x, y, button)
    if gamestate ~= 0 or button ~= 1 or self.busy or curtain.state ~= 0 then return end
    for _, b in ipairs(self.options) do
        if self:hit(b, x, y) then
            if self.walletPrompt then
                if b.option == "connect" then
                    if self.walletPrompt.state == "ask" then self:connectWallet() end
                elseif b.option == "skip" then
                    self:playWithoutWallet()
                elseif b.option == "continue" then
                    self:continueFound()
                elseif b.option == "fresh" then
                    self:startOverFound()
                end
            elseif self.confirming then
                if b.option == "yes" then
                    self.confirming = false
                    self:newGame()
                elseif b.option == "no" then
                    self.confirming = false
                end
            else
                self.selected = b.index
                self:choose(b.option)
            end
            return
        end
    end
end

-- the button under the mouse lights up
function menu:mousemoved(x, y)
    if self.busy or curtain.state ~= 0 then return end
    self.modalHover = nil
    for _, b in ipairs(self.options) do
        if self:hit(b, x, y) then
            if self:modal() then
                self.modalHover = b.option
            elseif b.index ~= self.selected then
                self.selected = b.index
                dj.play(sounds.ui.click, "static", "effect", 0.35)
            end
            return
        end
    end
end

----------------------------------------------------------------------- the backdrop

local function newEmber(anywhere)
    return { x = math.random(), y = anywhere and (0.3 + math.random() * 0.75) or 1.04, speed = 0.03 + math.random() * 0.05,
        sway = 0.004 + math.random() * 0.012, phase = math.random() * 6.3, size = 0.35 + math.random() * 0.55, heat = math.random() }
end

local function newFlake(anywhere)
    return { x = math.random(), y = anywhere and math.random() or -0.03, speed = 0.012 + math.random() * 0.028,
        phase = math.random() * 6.3, size = 0.3 + math.random() * 0.6, alpha = 0.08 + math.random() * 0.22 }
end

function menu:dropBackdrop()
    if self.backdrop and self.backdrop.canvas then self.backdrop.canvas:release() end
    self.backdrop = nil
end

function menu:update(dt)
    -- a journey begun without a wallet: say so once it's on screen
    if self.warnNoWallet and gamestate == 1 and not intro.active and curtain.state == 0 then
        self.warnNoWallet = nil
        showToast("No wallet: your journey is saved in this browser only, and your gold can't be traded."
            .. " Connect one any time in Settings (Esc).", 7)
    end
    if gamestate ~= 0 or intro.active then
        if self.backdrop then self:dropBackdrop() end
        return
    end
    dt = math.min(dt, 1 / 20) -- (the frame the backdrop bakes in is a long one)
    self.t = self.t + dt
    -- a frame of the title first, then Willowbrook is baked for behind it
    if not self.backdrop and self.t > 0.05 then
        self.backdrop = intro:bakeMap(BACKDROP_MAP)
        self.backdropAt = self.t
    end
    if not self.embers then
        self.embers, self.flakes = {}, {}
        for i = 1, 46 do self.embers[i] = newEmber(true) end
        for i = 1, 40 do self.flakes[i] = newFlake(true) end
    end
    for i, e in ipairs(self.embers) do
        e.y = e.y - e.speed * dt
        e.x = e.x + math.sin(self.t * 1.3 + e.phase) * e.sway * dt
        if e.y < 0.12 then self.embers[i] = newEmber(false) end
    end
    for i, f in ipairs(self.flakes) do
        f.y = f.y + f.speed * dt
        f.x = f.x + math.sin(self.t * 0.7 + f.phase) * 0.006 * dt
        if f.y > 1.03 then self.flakes[i] = newFlake(false) end
    end
    -- the wallet asked for in the popup has connected (and its save been read)
    local prompt = self.walletPrompt
    if prompt and prompt.state == "connecting" and onchain:connected() then
        local r = onchain.remote
        if r.saves ~= "1" or r.saveRead == "1" then self:walletConnected() end
    end
    settings:pollFullscreen(dt) -- (for Settings' Fullscreen: in the browser Esc can leave it without the game hearing)
end



-- soft shading, made once: a ramp (clear at the top, solid at the foot) and a
-- vignette, stretched over the screen
local shades = nil
local function getShades()
    if shades then return shades end
    local ramp = love.image.newImageData(1, 64)
    for y = 0, 63 do ramp:setPixel(0, y, 1, 1, 1, (y / 63) ^ 1.5) end
    local vignette = love.image.newImageData(64, 36)
    vignette:mapPixel(function(x, y)
        local dx, dy = (x + 0.5) / 32 - 1, (y + 0.5) / 18 - 1
        return 1, 1, 1, smooth((math.sqrt(dx * dx + dy * dy) / math.sqrt(2) - 0.3) / 0.7)
    end)
    shades = { ramp = love.graphics.newImage(ramp), vignette = love.graphics.newImage(vignette) }
    shades.ramp:setFilter("linear", "linear")
    shades.vignette:setFilter("linear", "linear")
    return shades
end

function menu:drawBackdrop(w, h)
    love.graphics.setColor(0.045, 0.03, 0.04, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local b = self.backdrop
    if b and b.canvas then
        local shown = smooth((self.t - self.backdropAt) / BACKDROP_FADE)
        local z = math.max(1, math.floor(scale * DRIFT_ZOOM + 0.5)) -- (whole pixels: no shimmer as it drifts)
        local mw, mh = b.canvas:getDimensions()
        local hw, hh = w / z / 2, h / z / 2
        local cx = DRIFT.x + DRIFT.rx * math.sin(self.t * 0.021)
        local cy = DRIFT.y + DRIFT.ry * math.sin(self.t * 0.033 + 1.3)
        cx = hw * 2 >= mw and mw / 2 or math.max(hw, math.min(mw - hw, cx))
        cy = hh * 2 >= mh and mh / 2 or math.max(hh, math.min(mh - hh, cy))
        love.graphics.push()
        love.graphics.translate(math.floor(w / 2 - cx * z + 0.5), math.floor(h / 2 - cy * z + 0.5))
        love.graphics.scale(z)
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(shown, shown, shown, shown)
        love.graphics.draw(b.canvas)
        love.graphics.setBlendMode("alpha")
        -- dusk, and the village's lamps and windows glowing through it
        love.graphics.setColor(0.07, 0.03, 0.11, 0.5 * shown)
        love.graphics.rectangle("fill", cx - hw - 4, cy - hh - 4, hw * 2 + 8, hh * 2 + 8)
        for _, l in ipairs(b.lights or {}) do
            local f = l.flicker and (0.85 + 0.15 * math.sin(self.t * 9 + l.seed) * math.sin(self.t * 5.3 + l.seed * 2)) or 1
            glow(l.x, l.y, l.radius, l.radius, l.color, 0.32 * f * shown)
        end
        love.graphics.pop()
    end

    -- darker under the title and the controls, and round the edges
    local s = getShades()
    love.graphics.setColor(0.035, 0.015, 0.03, 0.88)
    love.graphics.draw(s.ramp, 0, h * 0.45, 0, w, -h * 0.45 / 64)
    love.graphics.setColor(0.035, 0.015, 0.03, 0.92)
    love.graphics.draw(s.ramp, 0, h * 0.55, 0, w, h * 0.45 / 64)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.draw(s.vignette, 0, 0, 0, w / 64, h / 36)
    -- a fire's glow from below, and a dusk shadow behind the buttons
    glow(w / 2, h * 1.05, w * 0.55, h * 0.3, ORANGE, 0.1 + 0.02 * math.sin(self.t * 1.7), 14)
    shade(w / 2, h * 0.56, 120 * scale, 52 * scale, 0.55, 12)

    -- ash drifting down, embers rising
    for _, f in ipairs(self.flakes or {}) do
        local size = math.max(1, math.floor(f.size * scale * 0.5))
        love.graphics.setColor(0.86, 0.83, 0.8, f.alpha)
        love.graphics.rectangle("fill", math.floor(f.x * w), math.floor(f.y * h), size, size)
    end
    love.graphics.setBlendMode("add")
    for _, e in ipairs(self.embers or {}) do
        local a = clamp01((e.y - 0.12) / 0.45) * (0.6 + 0.4 * math.sin(self.t * 7 + e.phase * 3))
        local size = math.max(2, math.floor(e.size * scale * 0.6))
        local ex, ey = math.floor(e.x * w), math.floor(e.y * h)
        love.graphics.setColor(1, 0.45 + 0.35 * e.heat, 0.12 + 0.2 * e.heat, a * 0.22)
        love.graphics.rectangle("fill", ex - size, ey - size, size * 3, size * 3)
        love.graphics.setColor(1, 0.55 + 0.35 * e.heat, 0.2 + 0.25 * e.heat, a * 0.9)
        love.graphics.rectangle("fill", ex, ey, size, size)
    end
    love.graphics.setBlendMode("alpha")
end

----------------------------------------------------------------------- the title


-- returns the y below it
function menu:drawTitle(w, h)
    local f = fonts.title
    love.graphics.setFont(f)
    local tw = f:getWidth(TITLE)
    local x, y = math.floor((w - tw) / 2), math.floor(h * 0.065)
    -- (Pixelify Sans: its capitals stand 0.65 em on the baseline, the ascent 0.92 em)
    local ascent = f:getAscent()
    local capTop = y + ascent * 0.294
    local capH = ascent - ascent * 0.294
    local baseline = y + ascent

    glow(w / 2, capTop + capH * 0.5, tw * 0.62, capH * 1.25, ORANGE, 0.2 + 0.04 * math.sin(self.t * 1.9), 12)

    local o = math.max(2, math.floor(scale * 0.75))
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.print(TITLE, x, y + o * 3)
    love.graphics.setColor(0.2, 0.05, 0.02, 1)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then love.graphics.print(TITLE, x + dx * o, y + dy * o) end
        end
    end
    -- the letters, like hot metal: deep orange at the foot, gold, pale at the top
    local bands = { { 1, { 0.93, 0.36, 0.08 } }, { 0.62, { 1, 0.66, 0.2 } }, { 0.3, { 1, 0.9, 0.58 } } }
    for i, band in ipairs(bands) do
        if i > 1 then love.graphics.setScissor(0, 0, w, math.floor(capTop + capH * band[1])) end
        setColor(band[2], 1)
        love.graphics.print(TITLE, x, y)
    end
    -- now and then a glint runs along it: a soft band with a bright core
    local p = (self.t % SHINE_EVERY) / 0.9
    if p < 1 then
        local fade = math.sin(p * math.pi)
        local mid = x - 6 * scale + (tw + 12 * scale) * p
        for _, band in ipairs({ { 6, 0.22 }, { 2, 0.45 } }) do
            local bw = math.floor(band[1] * scale)
            love.graphics.setScissor(math.floor(mid - bw / 2), 0, bw, h)
            love.graphics.setColor(1, 1, 1, band[2] * fade)
            love.graphics.print(TITLE, x, y)
        end
    end
    love.graphics.setScissor()

    -- ALPHA TESTING between two lines
    local sf = fonts.menu
    love.graphics.setFont(sf)
    local sw = sf:getWidth(SUBTITLE)
    local sy = math.floor(baseline + 3.2 * scale)
    local mid = sy + sf:getHeight() * 0.55
    local lineW, gap = 20 * scale, 4 * scale
    local thick = math.max(2, math.floor(scale * 0.35))
    setColor(ORANGE, 0.75)
    love.graphics.rectangle("fill", (w - sw) / 2 - gap - lineW, mid - thick / 2, lineW, thick)
    love.graphics.rectangle("fill", (w + sw) / 2 + gap, mid - thick / 2, lineW, thick)
    setColor(GOLD, 0.9)
    diamond((w - sw) / 2 - gap - lineW, mid, scale * 1.1)
    diamond((w + sw) / 2 + gap + lineW, mid, scale * 1.1)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(SUBTITLE, (w - sw) / 2 + 2, sy + 2)
    love.graphics.setColor(1, 0.72, 0.42, 1)
    love.graphics.print(SUBTITLE, (w - sw) / 2, sy)
    return sy + sf:getHeight()
end

----------------------------------------------------------------------- the buttons




function menu:optionText(option, best, web)
    if option == "continue" then
        local place = places:name(best.save.map)
        return "Continue", place .. "  \194\183  " .. (best.source == "chain" and "saved on-chain " or "saved on this device ") .. ago(best.savedAt)
    elseif option == "new" then
        return "New Game", (best or self:hasChainSave()) and "Start over: your save is erased" .. (web and " (on-chain too)" or "")
            or "Begin your journey"
    elseif option == "settings" then
        return "Settings"
    end
    return "Quit"
end

-- returns the y below them
function menu:drawOptions(w, top, web)
    local choices = self:choices()
    self.selected = math.min(self.selected, #choices)
    local best = self:bestSave()
    local bw = 104 * scale
    local x = math.floor((w - bw) / 2)
    local y = top
    for i, option in ipairs(choices) do
        local primary = option == "continue" or option == "new"
        local bh = math.floor((primary and 13 or 8.5) * scale)
        local selected = i == self.selected and not self:modal()
        uiKit.button(x, y, bw, bh, selected, self.t)
        local title, detail = self:optionText(option, best, web)
        local alpha = selected and 1 or 0.72
        if primary then
            love.graphics.setFont(fonts.menuBig)
            setColor(CREAM, alpha)
            love.graphics.printf(title, x, y + 0.6 * scale, bw, "center")
            love.graphics.setFont(fonts.menuSmall)
            setColor(MUTED, selected and 1 or 0.6)
            love.graphics.printf(detail, x, y + 0.2 * scale + fonts.menuBig:getHeight(), bw, "center")
        else
            love.graphics.setFont(fonts.menu)
            setColor(CREAM, alpha)
            love.graphics.printf(title, x, y + (bh - fonts.menu:getHeight()) / 2, bw, "center")
            local right, cy = x + bw - 9 * scale, y + bh / 2
            if option == "settings" then
                tag(web and "Graphics \194\183 Wallet" or "Graphics \194\183 Keys", right, cy, { 1, 1, 1, 0.08 }, MUTED)
            elseif option == "quit" then
                tag("Esc", right, cy, { 1, 1, 1, 0.08 }, MUTED)
            end
        end
        table.insert(self.options, { x = x, y = y, w = bw, h = bh, option = option, index = i })
        y = y + bh + math.floor(2.8 * scale)
    end
    return y
end

-- the wallet, or what the game is waiting on
function menu:drawStatus(w, y, web)
    local r = onchain.remote
    local note, color = nil, MUTED
    if self.busy then
        local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
        note, color = self.busy .. dots, { 1, 0.85, 0.45 }
    elseif self.message then
        note, color = self.message, { 1, 0.55, 0.45 }
    elseif self.info then
        note, color = self.info, { 0.55, 0.95, 0.55 }
    elseif web then
        if onchain:connected() then
            local short = r.address:sub(1, 6) .. "..." .. r.address:sub(-4)
            if r.saves ~= "1" then
                note = "Wallet " .. short .. "  \194\183  on-chain saves aren't available on this server"
            elseif r.saveRead ~= "1" then
                note = "Wallet " .. short .. "  \194\183  reading your on-chain save..."
            elseif self:hasChainSave() then
                note, color = "Wallet " .. short .. "  \194\183  on-chain save found", { 0.55, 0.95, 0.55 }
            else
                note = "Wallet " .. short .. "  \194\183  no on-chain save yet: checkpoints will save on-chain"
            end
        elseif r.state == "working" then
            note = "Looking for your wallet..."
        else
            note = "Connect a wallet in Settings (or press C) to load or keep your journey on-chain"
        end
    end
    love.graphics.setFont(fonts.menuSmall)
    if note then
        setColor(color, 1)
        love.graphics.printf(note, w * 0.15, y, w * 0.7, "center")
    end
end

----------------------------------------------------------------------- tips


function menu:drawTip(w, bottom)
    local k = (self.t % TIP_TIME) / TIP_TIME
    local alpha = smooth(k / 0.08) * smooth((1 - k) / 0.08)
    local text = controls:fill(TIPS[math.floor(self.t / TIP_TIME) % #TIPS + 1])
    local f = fonts.menuSmall
    love.graphics.setFont(f)
    local label = "TIP"
    local lw = f:getWidth(label) + 3 * scale
    local total = lw + 2.5 * scale + f:getWidth(text)
    local x, y = math.floor((w - total) / 2), math.floor(bottom - f:getHeight() - 4 * scale)
    setColor(ORANGE, 0.9 * alpha)
    panel("fill", x, y - 0.3 * scale, lw, f:getHeight() + 0.6 * scale, math.floor(scale * 0.8))
    love.graphics.setColor(0.12, 0.05, 0.02, alpha)
    love.graphics.print(label, x + 1.5 * scale, y)
    love.graphics.setColor(0, 0, 0, 0.6 * alpha)
    love.graphics.print(text, x + lw + 2.5 * scale + 2, y + 2)
    setColor(CREAM, 0.92 * alpha)
    love.graphics.print(text, x + lw + 2.5 * scale, y)
end

----------------------------------------------------------------------- New Game, asked

function menu:drawConfirm(w, h, web)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local cw, ch = math.floor(132 * scale), math.floor(35 * scale)
    local cx, cy = math.floor((w - cw) / 2), math.floor((h - ch) / 2)
    local c = math.floor(scale * 2)
    glow(w / 2, h / 2, cw * 0.65, ch * 0.9, ORANGE, 0.12, 10)
    love.graphics.setColor(0.07, 0.045, 0.05, 0.97)
    panel("fill", cx, cy, cw, ch, c)
    love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.45)))
    setColor(ORANGE, 1)
    panel("line", cx, cy, cw, ch, c)
    love.graphics.setFont(fonts.menuBig)
    setColor(CREAM, 1)
    love.graphics.printf("Start a new game?", cx, cy + 3 * scale, cw, "center")
    love.graphics.setFont(fonts.menuSmall)
    setColor(MUTED, 1)
    local warning = "Your saved journey will be erased"
        .. ((web and self:hasChainSave()) and ", on-chain too (one wallet confirmation)." or ".")
    love.graphics.printf(warning, cx + 4 * scale, cy + 4 * scale + fonts.menuBig:getHeight(), cw - 8 * scale, "center")
    self:popupButtons(cx, cy, cw, ch, { { "yes", "[Y] Yes, start over" }, { "no", "[N] Keep my save" } })
end

-- a popup's two buttons, side by side along its foot ({ option, label }; dim: can't be pressed now)
function menu:popupButtons(cx, cy, cw, ch, list, dim)
    local bh = math.floor(8 * scale)
    local by = cy + ch - bh - 4 * scale
    for i, b in ipairs(list) do
        local bw = fonts.menuSmall:getWidth(b[2]) + 10 * scale
        local bx = math.floor(cx + cw / 2 + (i == 1 and -bw - 3 * scale or 3 * scale))
        local hot = self.modalHover == b[1] and not (dim and dim[b[1]])
        local alpha = (dim and dim[b[1]]) and 0.4 or 1
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], (hot and 0.45 or 0.2) * alpha)
        panel("fill", bx, by, bw, bh, math.floor(scale))
        setColor(ORANGE, (hot and 1 or 0.8) * alpha)
        panel("line", bx, by, bw, bh, math.floor(scale))
        setColor(CREAM, alpha)
        love.graphics.printf(b[2], bx, by + (bh - fonts.menuSmall:getHeight()) / 2, bw, "center")
        table.insert(self.options, { x = bx, y = by, w = bw, h = bh, option = b[1], modal = true })
    end
end

-- New Game in the browser with no wallet: connect one, or play without
-- (warned); connected, the journey found
function menu:drawWalletPrompt(w, h)
    local prompt = self.walletPrompt
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local f = fonts.menuSmall
    local cw = math.floor(150 * scale)
    local textW = cw - math.floor(12 * scale)
    local title, buttons, dim = "Connect a wallet?", { { "connect", "[C] Connect wallet" }, { "skip", "[N] Play without" } }, nil
    local lines = {
        { "With a wallet your journey is kept on-chain too, so Continue finds it in any browser, and the gold you earn can be traded for HEMI at Nova's stall.", MUTED },
        { "Without one, your journey is saved in this browser only (clearing the browser's data loses it), and your gold can't be traded.", { 1, 0.78, 0.35 } },
    }
    if prompt.state == "found" then
        local best = self:bestSave()
        title = "Welcome back!"
        buttons = { { "continue", "[Enter] Continue (recommended)" }, { "fresh", "[N] Start over" } }
        lines = {
            { "We found your journey: " .. places:name(best.save.map) .. "  \194\183  "
                .. (best.source == "chain" and "saved on-chain " or "saved on this device ") .. ago(best.savedAt) .. ".", { 0.55, 0.95, 0.55 } },
            { "Pick up where you left off, or start over (that erases it).", MUTED },
        }
    elseif prompt.state == "connecting" then
        table.insert(lines, { "Confirm in your wallet" .. string.rep(".", math.floor(love.timer.getTime() * 3) % 4), GOLD })
    elseif prompt.error then
        table.insert(lines, { prompt.error, { 1, 0.55, 0.45 } })
    end
    local textH = 0
    for _, l in ipairs(lines) do
        local _, wrapped = f:getWrap(l[1], textW)
        l.h = #wrapped * f:getHeight()
        textH = textH + l.h + math.floor(2 * scale)
    end
    local ch = math.floor(5 * scale) + fonts.menuBig:getHeight() + math.floor(2 * scale) + textH + math.floor(14 * scale)
    local cx, cy = math.floor((w - cw) / 2), math.floor((h - ch) / 2)
    local c = math.floor(scale * 2)
    glow(w / 2, h / 2, cw * 0.65, ch * 0.9, ORANGE, 0.12, 10)
    love.graphics.setColor(0.07, 0.045, 0.05, 0.97)
    panel("fill", cx, cy, cw, ch, c)
    love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.45)))
    setColor(ORANGE, 1)
    panel("line", cx, cy, cw, ch, c)
    love.graphics.setFont(fonts.menuBig)
    setColor(CREAM, 1)
    love.graphics.printf(title, cx, cy + math.floor(3 * scale), cw, "center")
    local ty = cy + math.floor(5 * scale) + fonts.menuBig:getHeight()
    love.graphics.setFont(f)
    for _, l in ipairs(lines) do
        setColor(l[2], 1)
        love.graphics.printf(l[1], cx + math.floor(6 * scale), ty, textW, "center")
        ty = ty + l.h + math.floor(2 * scale)
    end
    self:popupButtons(cx, cy, cw, ch, buttons, prompt.state == "connecting" and { connect = true } or dim)
end

function menu:draw()
    if gamestate ~= 0 then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local web = webBridge.isAvailable()
    self.options = {}

    self:drawBackdrop(w, h)
    local below = self:drawTitle(w, h)
    local y = self:drawOptions(w, math.floor(below + 7 * scale), web)
    self:drawStatus(w, y + math.floor(0.5 * scale), web)
    self:drawTip(w, h - math.floor(3 * scale))
    if self.confirming then self:drawConfirm(w, h, web) end
    if self.walletPrompt then self:drawWalletPrompt(w, h) end

    love.graphics.setLineWidth(1)
    setWhite()
end

-- kept for the old call in love.keypressed
function menu:select(key) end
