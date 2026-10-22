-- The Mana Well: Vera's stall by Willowbrook's north gate, open once Rick is
-- beaten. Staking locks the player's HEMI in the official veHemi contract on
-- Hemi (approve + createLock, see web/bridge.js "stake"); the veHEMI it gives
-- raises the Storm Staff's mana capacity (staff:maxMana).
--
-- Locked HEMI can't be taken out until the lock ends, so staking asks twice.

local webBridge = require("src/utilities/webBridge")

manaWell = {}
manaWell.active = false
manaWell.amountIndex = 4
manaWell.durationIndex = 5
manaWell.confirming = false
manaWell.message = nil
manaWell.buttons = {}

local VIOLET = {0.62, 0.42, 1}
local AMOUNTS = { 10, 25, 50, 100, 250, 500, 1000, 5000, "max" }
local DURATIONS = {
    { days = 13, label = "13 days" },
    { days = 30, label = "1 month" },
    { days = 91, label = "3 months" },
    { days = 182, label = "6 months" },
    { days = 365, label = "1 year" },
    { days = 730, label = "2 years" },
    { days = 1461, label = "4 years" },
}
local MAX_DAYS = 1461
local MIN_STAKE = 10

local function remote()
    return onchain.remote
end

local function number(text)
    return tonumber(text) or 0
end

-- 1234.5 -> "1,234.5"; small numbers keep one decimal
local function format(n)
    n = tonumber(n) or 0
    local text = n >= 100 and string.format("%d", math.floor(n)) or string.format("%.1f", n):gsub("%.0$", "")
    local whole, rest = text:match("^(%d+)(.*)$")
    if not whole then return text end
    whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return whole .. rest
end

function manaWell:amount()
    local choice = AMOUNTS[self.amountIndex]
    if choice == "max" then return math.floor(number(remote().hemiBalance)) end
    return choice
end

function manaWell:duration()
    return DURATIONS[self.durationIndex]
end

-- the largest preset this wallet can pay for (once its balance is known)
function manaWell:fitAmount()
    local r = remote()
    if r.veReady ~= "1" then return end
    local balance = number(r.hemiBalance)
    local amount = AMOUNTS[self.amountIndex]
    if amount ~= "max" and amount <= balance then return end
    for i = #AMOUNTS - 1, 1, -1 do
        if AMOUNTS[i] <= balance then
            self.amountIndex = i
            return
        end
    end
    self.amountIndex = 1
end

-- veHEMI needed for one more point of mana (nil at the cap)
function manaWell:nextPointAt(vePower)
    local bonus = staff.manaBonus(vePower)
    if bonus >= 200 then return nil end
    return 10 ^ ((bonus + 1) / 40) - 1
end

-- veHEMI a new lock would give today (it fades as the unlock date nears)
function manaWell:estimate(amount, days)
    return amount * days / MAX_DAYS
end

function manaWell:open()
    self.active = true
    self.confirming = false
    self.message = nil
    self.fitted = false
    dj.play(sounds.ui.menuOpen, "static", "effect")
    if webBridge.isAvailable() and not onchain:busy() then
        onchain:start(onchain:connected() and "vepower" or "status")
    end
end

function manaWell:close()
    self.active = false
    self.confirming = false
    dj.play(sounds.ui.menuClose, "static", "effect")
end

function manaWell:busy()
    return onchain:busy()
end

function manaWell:change(field, step)
    if self:busy() then return end
    self.confirming = false
    self.message = nil
    if field == "amount" then
        self.amountIndex = math.max(1, math.min(#AMOUNTS, self.amountIndex + step))
    else
        self.durationIndex = math.max(1, math.min(#DURATIONS, self.durationIndex + step))
    end
    dj.play(sounds.ui.click, "static", "effect", 0.6)
end

function manaWell:connect()
    if not webBridge.isAvailable() or onchain:busyNow() then return end
    self.message = nil
    onchain:start("connect")
end

function manaWell:refresh()
    if not webBridge.isAvailable() or onchain:busyNow() or not onchain:connected() then return end
    self.message = nil
    onchain:start("vepower")
end

function manaWell:stake()
    if not webBridge.isAvailable() or onchain:busyNow() then return end
    local r = remote()
    if not onchain:connected() then
        self:connect()
        return
    end
    local amount = self:amount()
    if amount < MIN_STAKE then
        self.message = "Stake at least " .. MIN_STAKE .. " HEMI."
        self.confirming = false
        return
    end
    if r.veReady == "1" and amount > number(r.hemiBalance) then
        self.message = "This wallet only has " .. format(r.hemiBalance) .. " HEMI."
        self.confirming = false
        return
    end
    if not self.confirming then
        self.confirming = true
        self.message = nil
        dj.play(sounds.ui.select, "static", "effect")
        return
    end
    self.confirming = false
    onchain:start("stake", { amount = amount, days = self:duration().days }, function(result, ok)
        if ok then
            dj.play(sounds.items.manaFull or sounds.ui.select, "static", "effect")
            showToast("veHEMI bound! Mana capacity: " .. staff:maxMana(), 4)
        end
    end)
end

function manaWell:viewTransaction()
    local url = remote().txUrl or ""
    if url ~= "" then love.system.openURL(url) end
end

function manaWell:keypressed(key)
    if key == "escape" or key == "tab" or key == "q" or key == "backspace" then
        if self.confirming then
            self.confirming = false
        else
            self:close()
        end
    elseif key == "left" or key == "a" then
        self:change("amount", -1)
    elseif key == "right" or key == "d" then
        self:change("amount", 1)
    elseif key == "up" or key == "w" then
        self:change("duration", 1)
    elseif key == "down" or key == "s" then
        self:change("duration", -1)
    elseif key == "e" or key == "return" or key == "kpenter" or key == "space" then
        self:stake()
    elseif key == "c" then
        self:connect()
    elseif key == "r" then
        self:refresh()
    elseif key == "v" then
        self:viewTransaction()
    end
end

function manaWell:mousepressed(x, y, button)
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

local function drawButton(def, bx, by, color)
    local bw = fonts.small:getWidth(def.label) + 4 * scale
    local bh = fonts.small:getHeight() + 2 * scale
    if def.alignRight then bx = bx - bw end
    if def.enabled then
        love.graphics.setColor(color[1], color[2], color[3], 0.25)
        love.graphics.rectangle("fill", bx, by, bw, bh, scale * 0.5, scale * 0.5)
        love.graphics.setColor(color[1], color[2], color[3], 1)
    else
        love.graphics.setColor(0.4, 0.37, 0.34, 1)
    end
    love.graphics.rectangle("line", bx, by, bw, bh, scale * 0.5, scale * 0.5)
    love.graphics.setColor(def.enabled and 1 or 0.6, def.enabled and 0.95 or 0.58, def.enabled and 1 or 0.55, 1)
    love.graphics.print(def.label, bx + 2 * scale, by + scale)
    return { x = bx, y = by, w = bw, h = bh, enabled = def.enabled, action = def.action }
end

function manaWell:draw()
    if not self.active then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local r = remote()
    local available = webBridge.isAvailable()
    local connected = available and onchain:connected()
    local working = available and self:busy()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local pad = 4 * scale
    local panelW = math.min(w * 0.82, 166 * scale)
    local panelH = 132 * scale
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2
    local border = math.max(2, math.floor(scale * 0.8))

    love.graphics.setColor(0.06, 0.04, 0.09, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, scale, scale)
    love.graphics.setLineWidth(border)
    love.graphics.setColor(VIOLET[1], VIOLET[2], VIOLET[3], 1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, scale, scale)

    -- header: the violet Hemi board from Vera's stall
    local logoSize = 14 * scale
    setWhite()
    love.graphics.draw(sprites.veHemi, panelX + pad, panelY + pad, 0, logoSize / sprites.veHemi:getWidth())
    love.graphics.setFont(fonts.dialogue)
    love.graphics.setColor(0.8, 0.66, 1, 1)
    love.graphics.print("veHEMI Mana Well", panelX + pad * 2 + logoSize, panelY + pad * 0.6)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.85, 0.82, 0.9, 1)
    love.graphics.printf("Stake more HEMI to increase your mana capacity: more fireballs and stronger staff beams. Vera binds it into veHEMI in the official veHemi contract on Hemi.",
        panelX + pad * 2 + logoSize, panelY + pad * 0.6 + fonts.dialogue:getHeight(), panelW - pad * 3 - logoSize, "left")

    -- details
    if not self.fitted and r.veReady == "1" and not working then
        self:fitAmount()
        self.fitted = true
    end
    local vePower = connected and number(r.vePower) or 0
    local amount = self:amount()
    local duration = self:duration()
    local gain = self:estimate(amount, duration.days)
    local manaNow = staff:maxMana()
    local unlocked = data.story.manaUnlocked or data.story.rickDefeated
    local manaAfter = unlocked and (100 + staff.manaBonus(vePower + gain)) or 100
    local known = connected and r.veReady == "1"

    self.buttons = {}
    local rows = {
        { "Your veHEMI", known and (format(vePower) .. "  (" .. (r.veLocks or "0") .. (r.veLocks == "1" and " lock)" or " locks)")) or "-" },
        { "Mana capacity", "100" .. (manaNow > 100 and ("  +" .. (manaNow - 100) .. " veHEMI  =  " .. manaNow) or ""),
            color = manaNow > 100 and {0.78, 0.6, 1} or nil },
        { "HEMI in wallet", known and format(r.hemiBalance) or "-" },
        { "Stake", (AMOUNTS[self.amountIndex] == "max" and "Max: " or "") .. format(amount) .. " HEMI", arrows = "amount" },
        { "Lock for", duration.label, arrows = "duration" },
        { "You'd get", "about " .. format(gain) .. " veHEMI   mana " .. manaNow .. " -> " .. manaAfter,
            color = manaAfter > manaNow and {0.55, 0.95, 0.55} or nil },
    }
    local nextAt = unlocked and known and manaAfter == manaNow and self:nextPointAt(vePower)
    if nextAt then
        table.insert(rows, { "", "next +1 mana at " .. format(nextAt) .. " veHEMI (" .. format(nextAt - vePower) .. " more)",
            color = {0.6, 0.56, 0.68} })
    end

    love.graphics.setFont(fonts.small)
    local rowH = fonts.small:getHeight() + scale * 2.2
    local y = panelY + 32 * scale
    local valueX = panelX + panelW * 0.34
    for _, row in ipairs(rows) do
        love.graphics.setColor(0.7, 0.66, 0.74, 1)
        love.graphics.print(row[1], panelX + pad * 1.5, y)
        local color = row.color or {0.97, 0.95, 0.98}
        if row.arrows then
            local field = row.arrows
            local left = drawButton({ label = "<", enabled = not working, action = function(self) self:change(field, -1) end },
                valueX, y - scale, VIOLET)
            table.insert(self.buttons, left)
            local textX = left.x + left.w + 2 * scale
            love.graphics.setColor(color[1], color[2], color[3], 1)
            love.graphics.print(row[2], textX, y)
            local right = drawButton({ label = ">", enabled = not working, action = function(self) self:change(field, 1) end },
                textX + fonts.small:getWidth(row[2]) + 2 * scale, y - scale, VIOLET)
            table.insert(self.buttons, right)
            love.graphics.setColor(0.55, 0.52, 0.6, 1)
            love.graphics.print(field == "amount" and "A / D" or "W / S", right.x + right.w + 3 * scale, y)
        else
            love.graphics.setColor(color[1], color[2], color[3], 1)
            love.graphics.print(row[2], valueX, y)
        end
        y = y + rowH
    end

    -- status line
    local status, statusColor = nil, {0.85, 0.82, 0.9}
    if not available then
        status = "Staking works in the browser version of the game, with an EVM wallet like MetaMask."
    elseif self.message then
        status, statusColor = self.message, {1, 0.55, 0.45}
    elseif working then
        local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
        status, statusColor = (r.step ~= "" and r.step or "Working") .. dots, {1, 0.85, 0.45}
    elseif self.confirming then
        status, statusColor = "Lock " .. format(amount) .. " HEMI for " .. duration.label .. "? Locked HEMI can't be withdrawn until the lock ends. Press E again to confirm, Esc to cancel.",
            {1, 0.7, 0.35}
    elseif r.state == "error" and (r.action == "stake" or r.action == "vepower") then
        status, statusColor = r.error, {1, 0.55, 0.45}
    elseif r.state == "done" and r.action == "stake" then
        status, statusColor = r.step, {0.55, 0.95, 0.55}
    elseif not connected then
        status = (r.wallet == "0") and "No browser wallet found. Install MetaMask or another EVM wallet."
            or "Connect a wallet to see your veHEMI and stake."
    elseif r.staking == "0" then
        status, statusColor = "Staking needs the Hemi network.", {1, 0.85, 0.45}
    elseif known and number(r.hemiBalance) < MIN_STAKE then
        status, statusColor = "Staking needs at least " .. MIN_STAKE .. " HEMI; this wallet has " .. format(r.hemiBalance) .. ".", {1, 0.85, 0.45}
    else
        status = "veHEMI fades as the unlock date nears: longer locks give more. Press E to stake."
    end
    love.graphics.setColor(statusColor[1], statusColor[2], statusColor[3], 1)
    love.graphics.printf(status or "", panelX + pad * 1.5, y + scale, panelW - pad * 3, "left")

    -- buttons
    local defs = {}
    if available and not connected then
        table.insert(defs, { label = "[C] Connect wallet", enabled = not working, action = self.connect })
    end
    table.insert(defs, { label = self.confirming and "[E] Confirm stake" or "[E] Stake HEMI", enabled = available and not working, action = self.stake })
    if connected then
        table.insert(defs, { label = "[R] Refresh", enabled = not working, action = self.refresh })
    end
    if (r.txUrl or "") ~= "" and r.action == "stake" then
        table.insert(defs, { label = "[V] View tx", enabled = true, action = self.viewTransaction })
    end
    table.insert(defs, { label = "[Esc] Leave", enabled = true, action = self.close })

    local bx = panelX + pad * 1.5
    local by = panelY + panelH - pad - fonts.small:getHeight() - 2 * scale
    for _, def in ipairs(defs) do
        local b = drawButton(def, bx, by, VIOLET)
        table.insert(self.buttons, b)
        bx = bx + b.w + 3 * scale
    end

    love.graphics.setLineWidth(1)
    setWhite()
end
