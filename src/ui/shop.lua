-- Villager trading window.
-- shop:open(title, keeperName, offers, greeting)
-- Each offer: { name, desc, icon = image, iconQuad = quad?, cost = {coins = 5} | {arrows = 6} | {bombs = 1},
--               give = function() end, canBuy = function() return ok, reason end, soldOut = function() end }
-- name, desc, thanks and priceLabel (shown instead of the cost, e.g. "+10 gold"
-- when selling) can also be functions, for rows whose text changes.

shop = {}
shop.active = false
shop.offers = {}
shop.selected = 1
shop.title = ""
shop.greeting = ""
shop.message = ""
shop.messageTimer = 0
shop.messageGood = true
shop.rows = {}

local COST_LABELS = { coins = "coins", arrows = "arrows", bombs = "bombs" }
local COST_LABELS_SINGLE = { coins = "coin", arrows = "arrow", bombs = "bomb" }

local function costLabel(resource, amount)
    if amount == 1 then return COST_LABELS_SINGLE[resource] end
    return COST_LABELS[resource]
end

local function owned(resource)
    if resource == "coins" then return data.money end
    if resource == "arrows" then return data.arrowCount end
    if resource == "bombs" then return data.bombCount end
    return 0
end

local function spend(resource, amount)
    if resource == "coins" then data.money = data.money - amount end
    if resource == "arrows" then data.arrowCount = data.arrowCount - amount end
    if resource == "bombs" then data.bombCount = data.bombCount - amount end
end

local function text(value)
    if type(value) == "function" then return value() end
    return value
end

local function costText(cost)
    for resource, amount in pairs(cost) do
        return amount .. " " .. costLabel(resource, amount)
    end
    return "free"
end

function shop:open(title, keeperName, offers, greeting)
    self.active = true
    self.title = title
    self.keeper = keeperName
    self.offers = offers
    self.greeting = greeting or ""
    self.selected = 1
    self.message = ""
    self.messageTimer = 0
    self.lastMouseX, self.lastMouseY = nil, nil
    dj.play(sounds.ui.menuOpen, "static", "effect")
end

function shop:close()
    self.active = false
    dj.play(sounds.ui.menuClose, "static", "effect")
end

function shop:update(dt)
    if not self.active then return end
    if self.messageTimer > 0 then
        self.messageTimer = self.messageTimer - dt
    end

    -- hovering only changes the selection when the mouse actually moves,
    -- so a resting cursor doesn't fight the keyboard
    local mx, my = love.mouse.getPosition()
    if mx ~= self.lastMouseX or my ~= self.lastMouseY then
        if self.lastMouseX then
            for i, row in ipairs(self.rows) do
                if mx >= row.x and mx <= row.x + row.w and my >= row.y and my <= row.y + row.h then
                    self.selected = i
                end
            end
        end
        self.lastMouseX, self.lastMouseY = mx, my
    end
end

function shop:say(text, good)
    self.message = text
    self.messageGood = good
    self.messageTimer = 2.2
end

-- "ok", "soldout", "poor" (can't afford) or "blocked" (e.g. quiver full),
-- plus the text shown in the price column
function shop:offerStatus(offer)
    if offer.soldOut and offer.soldOut() then
        return "soldout", "SOLD OUT"
    end
    if offer.canBuy then
        local ok = offer.canBuy()
        if not ok then
            return "blocked", offer.blockedLabel or "Not now"
        end
    end
    for resource, amount in pairs(offer.cost) do
        if owned(resource) < amount then
            return "poor", costText(offer.cost)
        end
    end
    return "ok", offer.priceLabel and text(offer.priceLabel) or costText(offer.cost)
end

function shop:buy()
    local offer = self.offers[self.selected]
    if not offer then return end

    if offer.soldOut and offer.soldOut() then
        self:say("That one's sold out.", false)
        dj.play(sounds.ui.click, "static", "effect", 1, 0.6)
        return
    end

    for resource, amount in pairs(offer.cost) do
        if owned(resource) < amount then
            self:say("You need " .. amount .. " " .. costLabel(resource, amount) .. " for that.", false)
            dj.play(sounds.ui.click, "static", "effect", 1, 0.6)
            return
        end
    end

    if offer.canBuy then
        local ok, reason = offer.canBuy()
        if not ok then
            self:say(reason or "You can't carry any more of that.", false)
            dj.play(sounds.ui.click, "static", "effect", 1, 0.6)
            return
        end
    end

    for resource, amount in pairs(offer.cost) do
        spend(resource, amount)
    end
    local thanks = offer.thanks
    local result = offer.give()
    if type(thanks) == "function" then thanks = thanks(result) end
    self:say(thanks or "Pleasure doing business!", true)
    dj.play(sounds.items.coin, "static", "effect")
end

function shop:move(step)
    self.selected = ((self.selected - 1 + step) % #self.offers) + 1
    dj.play(sounds.ui.select, "static", "effect", 0.6)
end

function shop:keypressed(key)
    if key == "w" or key == "up" then
        self:move(-1)
    elseif key == "s" or key == "down" then
        self:move(1)
    elseif key == "e" or key == "space" or key == "return" or key == "kpenter" then
        self:buy()
    elseif key == "escape" or key == "tab" or key == "q" or key == "backspace" then
        self:close()
    end
end

function shop:mousepressed(x, y, button)
    if button ~= 1 then
        self:close()
        return
    end
    for i, row in ipairs(self.rows) do
        if x >= row.x and x <= row.x + row.w and y >= row.y and y <= row.y + row.h then
            self.selected = i
            self:buy()
            return
        end
    end
end

local function drawIcon(offer, cx, cy, size)
    if not offer.icon then return end
    local iw, ih = offer.icon:getDimensions()
    if offer.iconQuad then
        local _, _, qw, qh = offer.iconQuad:getViewport()
        iw, ih = qw, qh
    end
    local s = math.max(1, math.floor(size / math.max(iw, ih)))
    setWhite()
    if offer.iconQuad then
        love.graphics.draw(offer.icon, offer.iconQuad, cx, cy, offer.iconRot or 0, s, s, iw / 2, ih / 2)
    else
        love.graphics.draw(offer.icon, cx, cy, offer.iconRot or 0, s, s, iw / 2, ih / 2)
    end
end

function shop:draw()
    if not self.active then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local pad = 4 * scale
    local rowH = 12 * scale
    local panelW = math.min(w * 0.8, 150 * scale)
    local headerH = 24 * scale
    local footerH = 26 * scale
    local panelH = headerH + rowH * #self.offers + footerH
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2
    local border = math.max(2, math.floor(scale * 0.8))

    love.graphics.setColor(0.07, 0.05, 0.06, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, scale, scale)
    love.graphics.setLineWidth(border)
    love.graphics.setColor(0.93, 0.84, 0.62, 1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, scale, scale)

    -- header
    love.graphics.setFont(fonts.dialogue)
    love.graphics.setColor(1, 0.86, 0.48, 1)
    love.graphics.print(self.title, panelX + pad, panelY + pad * 0.5)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.85, 0.82, 0.76, 1)
    love.graphics.printf(self.greeting, panelX + pad, panelY + pad * 0.5 + fonts.dialogue:getHeight(), panelW - pad * 2, "left")

    local wallet = string.format("%d coins   %d arrows   %d bombs", data.money, data.arrowCount, data.bombCount)
    love.graphics.setColor(0.98, 0.84, 0.36, 1)
    love.graphics.printf(wallet, panelX + pad, panelY + pad * 0.7, panelW - pad * 2, "right")

    -- offers
    self.rows = {}
    local listY = panelY + headerH
    for i, offer in ipairs(self.offers) do
        local y = listY + (i - 1) * rowH
        local row = { x = panelX + pad, y = y, w = panelW - pad * 2, h = rowH - scale }
        table.insert(self.rows, row)

        local status, label = self:offerStatus(offer)
        local unavailable = status ~= "ok"
        if i == self.selected then
            love.graphics.setColor(0.93, 0.84, 0.62, 0.18)
            love.graphics.rectangle("fill", row.x, row.y, row.w, row.h, scale * 0.5, scale * 0.5)
            love.graphics.setColor(0.93, 0.84, 0.62, 0.9)
            love.graphics.rectangle("line", row.x, row.y, row.w, row.h, scale * 0.5, scale * 0.5)
        end

        drawIcon(offer, row.x + rowH * 0.5, y + row.h / 2, rowH * 0.75)

        love.graphics.setFont(fonts.dialogue)
        if unavailable then
            love.graphics.setColor(0.55, 0.52, 0.5, 1)
        else
            love.graphics.setColor(0.97, 0.95, 0.90, 1)
        end
        love.graphics.print(text(offer.name), row.x + rowH * 1.1, y + (row.h - fonts.dialogue:getHeight()) / 2)

        -- price, or why it can't be bought right now
        if status == "poor" then
            love.graphics.setColor(1, 0.45, 0.4, 1)
        elseif unavailable then
            love.graphics.setColor(0.6, 0.57, 0.52, 1)
        else
            love.graphics.setColor(1, 0.84, 0.36, 1)
        end
        love.graphics.printf(label, row.x, y + (row.h - fonts.dialogue:getHeight()) / 2, row.w - pad, "right")
    end

    -- footer: description, feedback, controls
    local footY = listY + rowH * #self.offers
    local offer = self.offers[self.selected]
    love.graphics.setFont(fonts.small)
    if self.messageTimer > 0 then
        if self.messageGood then
            love.graphics.setColor(0.55, 0.95, 0.55, 1)
        else
            love.graphics.setColor(1, 0.5, 0.45, 1)
        end
        love.graphics.printf(self.message, panelX + pad, footY + pad * 0.3, panelW - pad * 2, "left")
    elseif offer then
        love.graphics.setColor(0.85, 0.82, 0.76, 1)
        love.graphics.printf(text(offer.desc) or "", panelX + pad, footY + pad * 0.3, panelW - pad * 2, "left")
    end
    love.graphics.setColor(0.6, 0.57, 0.52, 1)
    love.graphics.printf("W/S: choose     E: trade     Esc: leave",
        panelX + pad, panelY + panelH - fonts.small:getHeight() - pad * 0.5, panelW - pad * 2, "center")

    love.graphics.setLineWidth(1)
    setWhite()
end
