-- Title screen: Continue (load the last save) or New Game.
--
-- Saves live on this device (save.json) and, in the browser with a wallet
-- connected, in the AshfallSaves contract. Continue picks the newer of the
-- two. New Game wipes both: the on-chain slot is cleared with a transaction
-- (newGame) before the journey starts over.

local webBridge = require("src/utilities/webBridge")

menu = {}
menu.selected = 1
menu.confirming = false
menu.message = nil
menu.busy = nil        -- text shown while waiting for the wallet
menu.localSave = nil
menu.options = {}

local ORANGE = {1, 0.42, 0.1}

local MAP_NAMES = {
    test = "Willow Meadow", village = "Willowbrook", woods = "Whispering Woods",
    dungeon = "Old Dungeon", testCave = "Cave", test2 = "Forest Clearing",
}

function menu:open()
    self.selected = 1
    self.confirming = false
    self.message = nil
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
    curtain:call(data.map, data.playerX, data.playerY, "fade")
end

function menu:newGame()
    local chain = self:hasChainSave() and onchain:canSave()
    if not chain then
        self:startNewGame()
        return
    end
    -- clear the on-chain save first; the journey only starts over once it's gone
    self.busy = "Clearing your on-chain save: confirm in your wallet"
    self.message = nil
    onchain:start("newgame", nil, function(remote, ok)
        self.busy = nil
        if ok then
            self.chainCache = nil
            self:startNewGame()
        else
            self.message = "Your on-chain save wasn't cleared (" .. (remote.error or "error") .. "). Choose New Game to try again."
        end
    end)
end

function menu:choices()
    local list = {}
    if self:bestSave() then table.insert(list, "continue") end
    table.insert(list, "new")
    return list
end

function menu:choose(option)
    if option == "continue" then
        self:continueGame()
    elseif option == "new" then
        if self:bestSave() or self:hasChainSave() then
            self.confirming = true
            dj.play(sounds.ui.click, "static", "effect")
        else
            self:newGame()
        end
    end
end

function menu:keypressed(key)
    if gamestate ~= 0 or curtain.state ~= 0 then return end
    if self.busy then return end
    local choices = self:choices()
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

function menu:mousepressed(x, y, button)
    if gamestate ~= 0 or button ~= 1 or self.busy or curtain.state ~= 0 then return end
    for _, b in ipairs(self.options) do
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if self.confirming then
                if b.option == "yes" then
                    self.confirming = false
                    self:newGame()
                elseif b.option == "no" then
                    self.confirming = false
                end
            elseif b.option == "connect" then
                onchain:start("connect")
            else
                self.selected = b.index
                self:choose(b.option)
            end
            return
        end
    end
end

local function centered(text, font, y, color, alpha)
    love.graphics.setFont(font)
    local w = love.graphics.getWidth()
    love.graphics.setColor(0, 0, 0, 0.6 * (alpha or 1))
    love.graphics.printf(text, 3, y + 3, w, "center")
    love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
    love.graphics.printf(text, 0, y, w, "center")
end

function menu:draw()
    if gamestate ~= 0 then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local web = webBridge.isAvailable()
    local r = onchain.remote
    self.options = {}

    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)

    centered("ASHFALL", fonts.vsName, 14 * scale, {1, 0.86, 0.4})

    -- options
    local choices = self:choices()
    self.selected = math.min(self.selected, #choices)
    local best = self:bestSave()
    local boxW, boxH = 92 * scale, 15 * scale
    local y = 34 * scale
    for i, option in ipairs(choices) do
        local x = (w - boxW) / 2
        local selected = i == self.selected and not self.confirming
        love.graphics.setColor(0.07, 0.05, 0.06, selected and 0.92 or 0.75)
        love.graphics.rectangle("fill", x, y, boxW, boxH, scale, scale)
        love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.6)))
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], selected and 1 or 0.35)
        love.graphics.rectangle("line", x, y, boxW, boxH, scale, scale)

        local title, detail
        if option == "continue" then
            title = "Continue"
            local place = MAP_NAMES[best.save.map] or tostring(best.save.map)
            detail = place .. "  -  " .. (best.source == "chain" and "saved on-chain " or "saved on this device ") .. ago(best.savedAt)
        else
            title = "New Game"
            detail = (best or self:hasChainSave()) and "Start over: your save is erased" .. (web and " (on-chain too)" or "")
                or "Begin your journey"
        end
        love.graphics.setFont(fonts.menu)
        love.graphics.setColor(1, 0.95, 0.88, selected and 1 or 0.7)
        love.graphics.printf((selected and "> " or "") .. title, x, y + scale * 1.2, boxW, "center")
        love.graphics.setFont(fonts.menuSmall)
        love.graphics.setColor(0.8, 0.76, 0.7, selected and 1 or 0.6)
        love.graphics.printf(detail, x, y + scale * 1.2 + fonts.menu:getHeight(), boxW, "center")
        table.insert(self.options, { x = x, y = y, w = boxW, h = boxH, option = option, index = i })
        y = y + boxH + 4 * scale
    end

    -- wallet line (browser)
    love.graphics.setFont(fonts.menuSmall)
    local note, noteColor = nil, {0.8, 0.76, 0.7}
    if self.busy then
        local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
        note, noteColor = self.busy .. dots, {1, 0.85, 0.45}
    elseif self.message then
        note, noteColor = self.message, {1, 0.55, 0.45}
    elseif web then
        if onchain:connected() then
            local short = r.address:sub(1, 6) .. "..." .. r.address:sub(-4)
            if r.saves ~= "1" then
                note = "Wallet " .. short .. "  -  on-chain saves aren't available on this server"
            elseif r.saveRead ~= "1" then
                note = "Wallet " .. short .. "  -  reading your on-chain save..."
            elseif self:hasChainSave() then
                note, noteColor = "Wallet " .. short .. "  -  on-chain save found", {0.55, 0.95, 0.55}
            else
                note = "Wallet " .. short .. "  -  no on-chain save yet: checkpoints will save on-chain"
            end
        elseif r.state == "working" then
            note = "Looking for your wallet..."
        else
            note = "[C] Connect a wallet to load or keep your journey on-chain"
            local tw = fonts.menuSmall:getWidth(note) + 4 * scale
            table.insert(self.options, { x = (w - tw) / 2, y = y, w = tw, h = fonts.menuSmall:getHeight(), option = "connect" })
        end
    end
    if note then
        love.graphics.setColor(noteColor[1], noteColor[2], noteColor[3], 1)
        love.graphics.printf(note, w * 0.15, y, w * 0.7, "center")
    end

    -- New Game confirmation
    if self.confirming then
        local cw, ch = 130 * scale, 34 * scale
        local cx, cy = (w - cw) / 2, 36 * scale
        love.graphics.setColor(0.07, 0.05, 0.06, 0.97)
        love.graphics.rectangle("fill", cx, cy, cw, ch, scale, scale)
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        love.graphics.rectangle("line", cx, cy, cw, ch, scale, scale)
        love.graphics.setFont(fonts.menu)
        love.graphics.setColor(1, 0.95, 0.88, 1)
        love.graphics.printf("Start a new game?", cx, cy + 2 * scale, cw, "center")
        love.graphics.setFont(fonts.menuSmall)
        love.graphics.setColor(0.85, 0.82, 0.76, 1)
        local warning = "Your saved journey will be erased"
            .. ((web and self:hasChainSave()) and ", on-chain too (one wallet confirmation)." or ".")
        love.graphics.printf(warning, cx + 3 * scale, cy + 4 * scale + fonts.menu:getHeight(), cw - 6 * scale, "center")
        local by = cy + ch - 9 * scale
        for i, b in ipairs({ { "yes", "[Y] Yes, start over" }, { "no", "[N] Keep my save" } }) do
            local bw = fonts.menuSmall:getWidth(b[2]) + 6 * scale
            local bx = cx + cw / 2 + (i == 1 and -bw - 3 * scale or 3 * scale)
            love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
            love.graphics.rectangle("fill", bx, by, bw, 7 * scale, scale * 0.5, scale * 0.5)
            love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
            love.graphics.rectangle("line", bx, by, bw, 7 * scale, scale * 0.5, scale * 0.5)
            love.graphics.setColor(1, 0.95, 0.88, 1)
            love.graphics.printf(b[2], bx, by + scale, bw, "center")
            table.insert(self.options, { x = bx, y = by, w = bw, h = 7 * scale, option = b[1] })
        end
    end

    -- controls
    love.graphics.setFont(fonts.menuSmall)
    local lines = {
        "WASD / arrows: move     Space: roll     Shift: dodge     Mouse: aim and attack",
        "E: talk, trade, save at checkpoints, or Fireball (hold to charge)     Tab: items     Q: Shadow Step (once learned)",
        "M: menu and wallet     N: minimap     + / - or wheel: zoom     F3: free roam",
        web and "Up / Down and Enter to choose" or "Up / Down and Enter to choose     Backspace: fullscreen     Esc: quit",
    }
    local ly = h - (#lines * fonts.menuSmall:getHeight()) - 8 * scale
    for _, text in ipairs(lines) do
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf(text, 2, ly + 2, w, "center")
        love.graphics.setColor(0.92, 0.9, 0.85, 1)
        love.graphics.printf(text, 0, ly, w, "center")
        ly = ly + fonts.menuSmall:getHeight()
    end

    love.graphics.setLineWidth(1)
    setWhite()
end

-- kept for the old call in love.keypressed
function menu:select(key) end
