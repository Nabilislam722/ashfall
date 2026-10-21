-- The Hemi Exchange stall in Willowbrook trades the player's gold for HEMI
-- tokens. The exchange happens on-chain through the player's browser wallet,
-- so it only works in the web build. See docs/hemi-rewards.md for the
-- contract and server side.
--
-- The server only takes gold that is in the player's on-chain save (and only
-- as fast as a real journey earns it), so the window shows how much it will
-- take right now and why.

local webBridge = require("src/utilities/webBridge")

hemiExchange = {}
hemiExchange.active = false
hemiExchange.remote = {}   -- last state polled from web/bridge.js (same table as onchain.remote)
hemiExchange.lastSeq = 0   -- last exchange whose gold was already taken out
hemiExchange.message = nil
hemiExchange.buttons = {}

local ORANGE = {1, 0.42, 0.1}

function hemiExchange:open()
    self.active = true
    self.message = nil
    dj.play(sounds.ui.menuOpen, "static", "effect")
    if webBridge.isAvailable() then
        if not onchain:busy() then onchain:start("status") end
        self:poll()
    end
end

function hemiExchange:close()
    self.active = false
    dj.play(sounds.ui.menuClose, "static", "effect")
end

function hemiExchange:poll()
    onchain:poll()
end

-- called for every state polled from the page
function hemiExchange:onRemote(remote)
    self.remote = remote

    -- the server credited gold to the wallet: take it out of the game once
    local seq = tonumber(remote.seq) or 0
    if seq > self.lastSeq then
        self.lastSeq = seq
        local granted = tonumber(remote.granted) or 0
        if granted > 0 then
            data.money = math.max(0, data.money - granted)
        end
        local exchanged = tonumber(remote.exchangedRun)
        if exchanged then data.goldExchanged = exchanged end
        -- reloading the save on this device must not bring the gold back
        if granted > 0 and gamestate == 1 then
            local saved = saveState:readLocal()
            if saved then
                saved.gold = math.max(0, (tonumber(saved.gold) or 0) - granted)
                saved.exchanged = data.goldExchanged
                saveState:writeLocal(saveState:encode(saved))
            end
        end
    end
end

function hemiExchange:update(dt)
    -- polling lives in onchain:update
end

function hemiExchange:busy()
    return onchain:busy()
end

local function startAction(self, action, params)
    if not webBridge.isAvailable() or onchain:busyNow() then return end
    self.message = nil
    onchain:start(action, params)
end

function hemiExchange:connect()
    startAction(self, "connect")
end

function hemiExchange:switchNetwork()
    if (self.remote.address or "") == "" or self.remote.rightChain ~= "0" then return end
    startAction(self, "switch")
end

function hemiExchange:disconnect()
    if (self.remote.address or "") == "" then return end
    startAction(self, "disconnect")
end

function hemiExchange:redeem()
    if not webBridge.isAvailable() or onchain:busyNow() then return end
    local gold = data.money
    local pending = (self.remote.pending or "") ~= ""
    if gold <= 0 and not pending then
        self.message = "You don't have any gold yet. Open chests and beat Rick to earn some!"
        dj.play(sounds.ui.click, "static", "effect", 1, 0.6)
        return
    end
    startAction(self, "redeem", { gold = gold })
end

function hemiExchange:viewTransaction()
    local url = self.remote.txUrl or ""
    if url ~= "" then love.system.openURL(url) end
end

function hemiExchange:keypressed(key)
    if key == "escape" or key == "tab" or key == "q" or key == "backspace" then
        self:close()
    elseif key == "c" then
        self:connect()
    elseif key == "s" then
        self:switchNetwork()
    elseif key == "d" then
        self:disconnect()
    elseif key == "e" or key == "space" or key == "return" or key == "kpenter" then
        self:redeem()
    elseif key == "v" then
        self:viewTransaction()
    end
end

function hemiExchange:mousepressed(x, y, button)
    if button ~= 1 then
        self:close()
        return
    end
    for _, b in ipairs(self.buttons) do
        if b.enabled and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            b.action(self)
            return
        end
    end
end

local function shortAddress(address)
    if not address or #address < 12 then return address or "" end
    return address:sub(1, 6) .. "..." .. address:sub(-4)
end

local function drawButton(def, bx, by)
    local bw = fonts.small:getWidth(def.label) + 4 * scale
    local bh = fonts.small:getHeight() + 2 * scale
    if def.alignRight then bx = bx - bw end
    if def.enabled then
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
        love.graphics.rectangle("fill", bx, by, bw, bh, scale * 0.5, scale * 0.5)
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    else
        love.graphics.setColor(0.4, 0.37, 0.34, 1)
    end
    love.graphics.rectangle("line", bx, by, bw, bh, scale * 0.5, scale * 0.5)
    love.graphics.print(def.label, bx + 2 * scale, by + scale)
    return { x = bx, y = by, w = bw, h = bh, enabled = def.enabled, action = def.action }
end

local function tokensFor(gold, rate)
    if not rate or rate <= 0 then return nil end
    local tokens = gold / rate
    if tokens == math.floor(tokens) then return tostring(tokens) end
    return string.format("%.2f", tokens)
end

function hemiExchange:draw()
    if not self.active then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local remote = self.remote
    local available = webBridge.isAvailable()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local pad = 4 * scale
    local panelW = math.min(w * 0.8, 160 * scale)
    local panelH = 130 * scale
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2
    local border = math.max(2, math.floor(scale * 0.8))

    love.graphics.setColor(0.07, 0.05, 0.06, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, scale, scale)
    love.graphics.setLineWidth(border)
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, scale, scale)

    -- header
    local logoSize = 14 * scale
    setWhite()
    love.graphics.draw(sprites.hemi, panelX + pad, panelY + pad, 0, logoSize / sprites.hemi:getWidth())
    love.graphics.setFont(fonts.dialogue)
    love.graphics.setColor(1, 0.6, 0.3, 1)
    love.graphics.print("Hemi Exchange", panelX + pad * 2 + logoSize, panelY + pad * 0.6)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.85, 0.82, 0.76, 1)
    love.graphics.printf("Nova trades the gold you earn on your adventure for real HEMI tokens on the Hemi network.",
        panelX + pad * 2 + logoSize, panelY + pad * 0.6 + fonts.dialogue:getHeight(), panelW - pad * 3 - logoSize, "left")

    -- details
    local symbol = (remote.symbol and remote.symbol ~= "") and remote.symbol or "HEMI"
    local rate = tonumber(remote.rate)
    local gold = data.money
    local working = available and self:busy()
    local hasAddress = (remote.address or "") ~= ""
    local target = (remote.chain or "") ~= "" and remote.chain or "Hemi"
    local wrongChain = hasAddress and remote.rightChain == "0"
    local rows = {
        { "Your gold", tostring(gold) .. (rate and ("   (= " .. tokensFor(gold, rate) .. " " .. symbol .. ")") or "") },
        { "Exchange rate", rate and (rate .. " gold = 1 " .. symbol) or "-" },
        { "Wallet limit", (remote.cap and remote.cap ~= "") and (remote.cap .. " gold" .. ((remote.remaining or "") ~= "" and ("  (" .. remote.remaining .. " left)") or "")) or "-" },
        { "Network", (hasAddress and (remote.walletChain or "") ~= "") and remote.walletChain or target,
            color = wrongChain and {1, 0.72, 0.3} or nil,
            button = wrongChain and { label = "[S] Switch to " .. target, enabled = not working, action = self.switchNetwork } or nil },
        { "Wallet", hasAddress and shortAddress(remote.address) or "Not connected",
            button = hasAddress and { label = "[D] Disconnect", enabled = not working, action = self.disconnect } or nil },
    }
    if hasAddress and (remote.available or "") ~= "" then
        local available = tonumber(remote.available) or 0
        table.insert(rows, 4, { "Exchangeable now", available .. " gold" .. (available > 0 and ("  (= " .. tokensFor(available, rate or 10) .. " " .. symbol .. ")") or ""),
            color = available > 0 and {0.55, 0.95, 0.55} or {1, 0.72, 0.3} })
    end
    if (remote.pending or "") ~= "" then
        table.insert(rows, { "Reserved for you", remote.pending .. " " .. symbol .. "  (press E to claim)" })
    end

    self.buttons = {}
    love.graphics.setFont(fonts.small)
    local rowH = fonts.small:getHeight() + scale * 2.2
    local y = panelY + 30 * scale
    for _, row in ipairs(rows) do
        love.graphics.setColor(0.7, 0.66, 0.6, 1)
        love.graphics.print(row[1], panelX + pad * 1.5, y)
        local color = row.color or {0.97, 0.95, 0.9}
        love.graphics.setColor(color[1], color[2], color[3], 1)
        love.graphics.print(row[2], panelX + panelW * 0.36, y)
        if row.button then
            row.button.alignRight = true
            table.insert(self.buttons, drawButton(row.button, panelX + panelW - pad * 1.5, y - scale))
        end
        y = y + rowH
    end

    -- status line
    local status, color = nil, {0.85, 0.82, 0.76}
    if not available then
        status = "Redeeming works in the browser version of the game, with an EVM wallet like MetaMask."
    elseif self.message then
        status, color = self.message, {1, 0.55, 0.45}
    elseif remote.state == "working" then
        local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
        status, color = (remote.step or "Working") .. dots, {1, 0.85, 0.45}
    elseif remote.state == "error" then
        status, color = remote.error, {1, 0.55, 0.45}
    elseif remote.state == "done" then
        status, color = remote.step, {0.55, 0.95, 0.55}
    elseif (remote.exchange or "") ~= "" then
        status, color = remote.exchange, {1, 0.85, 0.45}
    elseif (remote.address or "") == "" then
        status = (remote.wallet == "0") and "No browser wallet found. Install MetaMask or another EVM wallet."
            or "Connect a wallet to start."
    elseif wrongChain then
        status, color = "Your wallet is on " .. (remote.walletChain or "another network") .. ". Press S to switch to " .. target .. ".", {1, 0.85, 0.45}
    elseif (remote.limitMessage or "") ~= "" and (tonumber(remote.available) or 0) <= 0 and (remote.pending or "") == "" then
        status, color = remote.limitMessage, {1, 0.85, 0.45}
    else
        status = "Ready. Press E to exchange your gold."
    end
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.printf(status or "", panelX + pad * 1.5, y + scale * 2, panelW - pad * 3, "left")

    -- buttons
    local redeemLabel = "[E] Exchange gold"
    if gold <= 0 and (remote.pending or "") ~= "" then redeemLabel = "[E] Claim " .. symbol end
    local defs = {}
    if not hasAddress then
        table.insert(defs, { label = "[C] Connect wallet", enabled = available and not working, action = self.connect })
    end
    table.insert(defs, { label = redeemLabel, enabled = available and not working, action = self.redeem })
    if (remote.txUrl or "") ~= "" then
        table.insert(defs, { label = "[V] View tx", enabled = true, action = self.viewTransaction })
    end
    table.insert(defs, { label = "[Esc] Leave", enabled = true, action = self.close })

    love.graphics.setFont(fonts.small)
    local bx = panelX + pad * 1.5
    local by = panelY + panelH - pad - fonts.small:getHeight() - 2 * scale
    for _, def in ipairs(defs) do
        local button = drawButton(def, bx, by)
        table.insert(self.buttons, button)
        bx = bx + button.w + 3 * scale
    end

    love.graphics.setLineWidth(1)
    setWhite()
end
