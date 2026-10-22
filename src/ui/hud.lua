-- the bars and stats row are drawn at a fraction of the game scale
function hudScale()
    return scale * 0.6
end

-- The health, stamina and mana panel (sprites/ui/hud): a bone frame with the
-- hero in its ring, a long trough along the top for health and two short ones
-- under it, stamina left and mana right; Shadow Step sits in the little socket
-- under the ring. Places are in the panel's own pixels.
local PANEL = {
    w = 163, h = 40,
    hp = { x = 38, y = 10, w = 117 },
    stamina = { x = 41, y = 19, w = 46 },
    mana = { x = 95, y = 19, w = 46 },
    ring = { x = 22, y = 21.5 },          -- the middle of the portrait ring
    socket = { x = 46, y = 32, r = 6 },   -- the middle of the socket under it
}
local HIT_FLASH = 0.35
local hud = { hpTrail = nil, lastHp = nil, staminaFlash = 0, hitFlash = 0, quads = {} }

local function panelScale()
    return hudScale() * 0.6
end

-- where the stats row goes, under the panel
local function walletY()
    return 6 + PANEL.h * panelScale() + 2 * hudScale()
end

-- first free y below the panel and the stats row
function hudBottomY()
    return math.floor(walletY() + 8 * hudScale())
end

-- the stamina bar flashes when there isn't enough for what was tried
function hudFlashStamina()
    hud.staminaFlash = 0.6
end

function drawHUD()
    if pause.active then return end
    drawBars()
    drawWallet()
    --drawItemBox()
    --drawMoney()
end

local function quad(image, x, y, w, h)
    local key = tostring(image) .. x .. "," .. y .. "," .. w .. "," .. h
    if not hud.quads[key] then
        hud.quads[key] = love.graphics.newQuad(x, y, w, h, image:getDimensions())
    end
    return hud.quads[key]
end

-- how many of a trough's pixels `fill` (0..1) covers
local function filled(slot, fill)
    return math.floor(slot.w * math.max(0, math.min(1, fill)) + 0.5)
end

-- the strip for `kind` laid in its trough, `fill` (0..1) of it full
local function drawFill(kind, px, py, fill, tint)
    local slot, strip = PANEL[kind], sprites.hud.fills[kind]
    local w = filled(slot, fill)
    if w <= 0 then return end
    local s = panelScale()
    local t = tint or { 1, 1, 1 }
    love.graphics.setColor(t[1], t[2], t[3], 1)
    love.graphics.draw(strip, quad(strip, 0, 0, w, strip:getHeight()), px + slot.x * s, py + slot.y * s, 0, s, s)
end

-- a number beside the panel, its middle at y, with a drop shadow
local function panelLabel(text, x, y, color)
    local hs = hudScale()
    love.graphics.setFont(fonts.hudSmall)
    local ty = y - fonts.hudSmall:getHeight() / 2
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.print(text, x + hs * 0.4, ty + hs * 0.4)
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.print(text, x, ty)
    setWhite()
end

-- the hero in the ring: red for a moment after a hit, grey when down
local function drawPortrait(px, py, hp)
    local s = panelScale()
    if hp <= 0 then
        love.graphics.setColor(0.35, 0.35, 0.42, 1)
    elseif hud.hitFlash > 0 then
        local f = hud.hitFlash / HIT_FLASH
        love.graphics.setColor(1, 1 - 0.65 * f, 1 - 0.65 * f, 1)
    else
        setWhite()
    end
    -- the figure (16x18 at the top left of its 19x21 frame) centred in the ring
    love.graphics.draw(sprites.npc.hero, px + (PANEL.ring.x - 8) * s, py + math.floor(PANEL.ring.y - 10) * s, 0, s, s)
    setWhite()
end

-- Shadow Step in the socket, with its key and a recharge ring
local function drawShadowSocket(px, py)
    local s = panelScale()
    local icon = sprites.items.shadowStep
    local cx, cy = px + PANEL.socket.x * s, py + PANEL.socket.y * s
    local ready = player:shadowStepReady()
    if ready then setWhite() else love.graphics.setColor(0.45, 0.45, 0.5, 1) end
    local is = s * 10 / icon:getWidth()
    love.graphics.draw(icon, cx, cy, 0, is, is, icon:getWidth() / 2, icon:getHeight() / 2)
    if not ready then
        local progress = 1 - math.max(0, player.shadowCooldown) / player.shadowCooldownMax
        love.graphics.setColor(0.7, 0.5, 1, 0.9)
        love.graphics.setLineWidth(math.max(2, math.floor(s * 0.8)))
        love.graphics.arc("line", "open", cx, cy, PANEL.socket.r * s, -math.pi / 2, -math.pi / 2 + progress * math.pi * 2)
        love.graphics.setLineWidth(1)
    end
    panelLabel("Q", px + 53 * s, py + 32 * s, { 0.8, 0.65, 1 })
end

-- health, stamina and mana, top left
function drawBars()
    local s = panelScale()
    local px, py = 6, 6
    local dt = love.timer.getDelta()
    local now = love.timer.getTime()

    -- health: a hit flashes the portrait and leaves a pale trail that drains
    -- away; at a heart or less the bar pulses
    local maxHp = math.max(1, data.maxHealth)
    local hp = math.max(0, player.health)
    if hud.lastHp and hp < hud.lastHp then hud.hitFlash = HIT_FLASH end
    hud.lastHp = hp
    hud.hitFlash = math.max(0, hud.hitFlash - dt)
    hud.hpTrail = hud.hpTrail or hp
    if hp >= hud.hpTrail then hud.hpTrail = hp else hud.hpTrail = math.max(hp, hud.hpTrail - dt * 1.2) end
    hud.staminaFlash = math.max(0, hud.staminaFlash - dt)

    setWhite()
    love.graphics.draw(sprites.hud.panel, px, py, 0, s, s)
    drawPortrait(px, py, hp)

    local trailW, fillW = filled(PANEL.hp, hud.hpTrail / maxHp), filled(PANEL.hp, hp / maxHp)
    if trailW > fillW then
        drawFill("hp", px, py, hud.hpTrail / maxHp)
        love.graphics.setColor(1, 0.95, 0.85, 0.6)
        love.graphics.rectangle("fill", px + (PANEL.hp.x + fillW) * s, py + PANEL.hp.y * s, (trailW - fillW) * s,
            sprites.hud.fills.hp:getHeight() * s)
    end
    local hpTint = nil
    if hp <= 1 and hp > 0 then
        local pulse = 0.75 + 0.25 * math.sin(now * 8)
        hpTint = { 1, pulse, pulse }
    end
    drawFill("hp", px, py, hp / maxHp, hpTint)

    -- stamina (dodge, roll, Shadow Step); it flashes red when there wasn't enough
    drawFill("stamina", px, py, player.stamina / player.staminaMax)
    if hud.staminaFlash > 0 then
        local a = hud.staminaFlash * (0.6 + 0.4 * math.sin(now * 30))
        love.graphics.setColor(1, 0.2, 0.15, a)
        love.graphics.rectangle("fill", px + PANEL.stamina.x * s, py + PANEL.stamina.y * s, PANEL.stamina.w * s,
            sprites.hud.fills.stamina:getHeight() * s)
    end

    -- mana: full, it glows
    local maxMana = staff:maxMana()
    local manaTint = nil
    if staff.mana >= maxMana then
        local pulse = 0.85 + 0.15 * math.sin(now * 10)
        manaTint = { pulse, pulse + 0.1, 1 }
    end
    drawFill("mana", px, py, staff.mana / maxMana, manaTint)
    setWhite()

    if data.skills.shadowStep then drawShadowSocket(px, py) end

    -- the numbers, beside the panel
    local lx = px + (PANEL.w + 2) * s
    local hpText = (hp % 1 == 0 and string.format("%d", hp) or string.format("%.1f", hp)) .. "/" .. maxHp
    panelLabel(hpText, lx, py + 12 * s, { 1, 0.8, 0.78 })
    local amount = math.floor(staff.mana) .. "/" .. maxMana
    panelLabel(amount, lx, py + 24 * s, { 0.75, 0.88, 1 })
    if maxMana > 100 then
        panelLabel("(+" .. (maxMana - 100) .. " veHEMI)", lx + fonts.hudSmall:getWidth(amount) + hudScale() * 2,
            py + 24 * s, { 0.78, 0.6, 1 })
    end
end

-- gold, arrows, bombs and loot under the panel
function drawWallet()
    local hs = hudScale()
    local x = 6
    local y = walletY()
    local iconSize = 6 * hs
    local gap = 22 * hs

    local entries = {
        { sprite = sprites.hud.coin, count = data.money },
        { sprite = sprites.items.arrow, count = data.arrowCount, rot = math.pi / -4 },
        { sprite = sprites.items.bomb, count = data.bombCount },
    }
    local ears, rares = mobLoot:totals()
    if ears > 0 then
        table.insert(entries, { sprite = sprites.items.mobLoot, quad = mobLoot:quad("batEar"), count = ears })
    end
    if rares > 0 then
        table.insert(entries, { sprite = sprites.items.mobLoot, quad = mobLoot:quad("soulGem"), count = rares })
    end

    drawFireballKey(x + #entries * gap, y, iconSize, hs)

    love.graphics.setFont(fonts.hudSmall)
    for i, entry in ipairs(entries) do
        local ex = x + (i - 1) * gap
        local w, h = entry.sprite:getDimensions()
        if entry.quad then
            local _, _, qw, qh = entry.quad:getViewport()
            w, h = qw, qh
        end
        local s = iconSize / math.max(w, h)
        setWhite()
        if entry.quad then
            love.graphics.draw(entry.sprite, entry.quad, ex + iconSize / 2, y + iconSize / 2, 0, s, s, w / 2, h / 2)
        else
            love.graphics.draw(entry.sprite, ex + iconSize / 2, y + iconSize / 2, entry.rot or 0, s, s, w / 2, h / 2)
        end
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.print(entry.count, ex + iconSize + hs * 1.4, y + hs * 1.4)
        setWhite()
        love.graphics.print(entry.count, ex + iconSize + hs, y + hs)
    end
end

-- the fireball with its key: lit when there's mana enough to cast one
function drawFireballKey(x, y, iconSize, hs)
    local icon = sprites.effects.fireball
    local s = iconSize / math.max(icon:getWidth(), icon:getHeight()) * 1.3
    local ready = staff.mana >= fireballs.COST
    if ready then setWhite() else love.graphics.setColor(0.45, 0.45, 0.5, 1) end
    love.graphics.draw(icon, x + iconSize / 2, y + iconSize / 2, -math.pi / 4, s, s, icon:getWidth() / 2, icon:getHeight() / 2)
    -- its key held: a ring fills as the fireball charges
    local charge = fireballs.charge
    if charge and charge.charging then
        love.graphics.setColor(1, 0.55, 0.2, charge.full and 1 or 0.85)
        love.graphics.setLineWidth(math.max(2, math.floor(hs * 0.6)))
        love.graphics.arc("line", "open", x + iconSize / 2, y + iconSize / 2, iconSize * 0.75, -math.pi / 2, -math.pi / 2 + charge.power * math.pi * 2)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setFont(fonts.hudGoal)
    love.graphics.setColor(0, 0, 0, 0.8)
    local key = fireballs.KEY:upper()
    love.graphics.print(key, x + iconSize * 0.62 + hs * 0.4, y + iconSize * 0.25 + hs * 0.4)
    love.graphics.setColor(1, 0.92, 0.75, 1)
    love.graphics.print(key, x + iconSize * 0.62, y + iconSize * 0.25)
    setWhite()
end

function drawMoney()
    local mx = love.graphics.getWidth() - 23*scale
    local my = love.graphics.getHeight() - 10*scale
    local tx = love.graphics.getWidth() - 12*scale
    local ty = love.graphics.getHeight() - 11*scale
    setWhite()
    love.graphics.draw(sprites.hud.coin, mx, my, nil, 1.5*scale)
    love.graphics.setFont(fonts.coins)
    love.graphics.print(data.money, tx, ty)
end

function drawItemBox()
    -- Below the hearts
    --local bx = 6
    --local by = 16*scale

    -- Upper-right
    local bx = love.graphics.getWidth() - 19*scale
    local by = 6

    love.graphics.setColor(0,0,0, 0.35)
    love.graphics.rectangle("fill", bx+1, by+1, 16*scale, 16*scale)
    setWhite()
    love.graphics.draw(sprites.hud.itemBox, bx, by, nil, scale)

    local ammoCount = -1
    local maxed = false
    if data.item.x == 2 then
        ammoCount = data.bombCount
        if data.bombCount == data.maxBombCount then
            maxed = true
        end
    elseif data.item.x == 3 then
        ammoCount = data.arrowCount
        if data.arrowCount == data.maxArrowCount then
            maxed = true
        end
    end
    
    if ammoCount > -1 then
        love.graphics.setColor(0,0,0, 0.35)
        love.graphics.rectangle("fill", bx+(3*scale), by+(20*scale), 11*scale, 7*scale)
        setWhite()
        love.graphics.draw(sprites.hud.ammoBox, bx+(2.5*scale), by+(19*scale), nil, scale)

        love.graphics.setFont(fonts.ammo)
        if maxed then love.graphics.setColor(0,1,0,1) end
        love.graphics.printf(ammoCount, bx+(4.5*scale), by+(20*scale), 9.5*scale, "center")
        --love.graphics.print(ammoCount, bx+(3*scale), by+(20*scale))
        setWhite()
    end

    local spr = sprites.items.boomerang
    local offX = -1.5
    local offY = -1.5
    local scaleMod = 1.25
    if data.item.x == 1 then -- boomerang
        spr = sprites.items.boomerang
    elseif data.item.x == 2 then -- bomb
        spr = sprites.items.bomb
        offX = 2.3
        offY = 2.8
        scaleMod = 1.1
    elseif data.item.x == 3 then -- bow
        spr = sprites.items.bowIcon
        offX = 4.2
        offY = 2.3
        scaleMod = 0.17
    end
    love.graphics.draw(spr, bx + (offX * scale), by + (offY * scale), nil, scale * scaleMod)
end
