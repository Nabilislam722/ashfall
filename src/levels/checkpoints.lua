-- Checkpoint shrines placed in a map's "Checkpoints" object layer.
--
-- Walking up to one lights its crystal and saves the journey (saveState:saveNow):
-- on this device, and on-chain when a wallet is connected. Pressing E at a lit
-- checkpoint saves again. "Continue" on the title screen starts from the last save.

checkpoints = {}

local TOUCH_RADIUS = 20
local quads = nil

local function getQuads()
    if not quads then
        local sheet = sprites.environment.checkpoint
        local w, h = sheet:getDimensions()
        quads = {
            base = love.graphics.newQuad(0, 0, 16, 10, w, h),
            off = love.graphics.newQuad(16, 0, 8, 14, w, h),
            on = love.graphics.newQuad(24, 0, 8, 14, w, h),
        }
    end
    return quads
end

function loadCheckpoints(map, mapName)
    for i = #checkpoints, 1, -1 do
        table.remove(checkpoints, i)
    end
    if not map.layers["Checkpoints"] then return end

    for _, obj in ipairs(map.layers["Checkpoints"].objects) do
        local id = (obj.name and obj.name ~= "") and obj.name or tostring(obj.id)
        local cp = {
            key = mapName .. ":" .. id,
            x = obj.x + (obj.width or 16) / 2,
            y = obj.y + (obj.height or 16),
            timer = math.random() * 6,
            sparkles = {},
        }
        spawnWall(cp.x - 7, cp.y - 6, 14, 6)
        table.insert(checkpoints, cp)
    end
end

local function isActive(cp)
    return data.checkpoints[cp.key] == true
end

local function burst(cp)
    for i = 1, 18 do
        local angle = (i / 18) * math.pi * 2
        table.insert(cp.sparkles, {
            x = cp.x, y = cp.y - 18,
            vx = math.cos(angle) * (25 + math.random() * 20),
            vy = math.sin(angle) * (25 + math.random() * 20) - 15,
            life = 0.6 + math.random() * 0.4,
        })
    end
end

local function save(cp)
    data.lastCheckpoint = cp.key
    saveState:saveNow()
end

local function activate(cp)
    data.checkpoints[cp.key] = true
    floatTexts:spawn(cp.x, cp.y - 30, "Checkpoint!", {1, 0.6, 0.25}, {big = true, life = 1.4})
    save(cp)
    dj.play(sounds.ui.select, "static", "effect", 1, 1.3)
    burst(cp)
end

local function nearby()
    for _, cp in ipairs(checkpoints) do
        if distanceBetween(cp.x, cp.y - 6, player:getX(), player:getY()) < TOUCH_RADIUS + 10 then return cp end
    end
end

-- E at a lit checkpoint saves again; returns true when it did
function checkpoints:tryInteract()
    local cp = nearby()
    if not cp or not isActive(cp) or saveState.chainSaving then return false end
    floatTexts:spawn(cp.x, cp.y - 30, "Saved!", {1, 0.6, 0.25}, {life = 1.1})
    dj.play(sounds.ui.select, "static", "effect", 0.8, 1.5)
    burst(cp)
    save(cp)
    return true
end

function checkpoints:update(dt)
    for _, cp in ipairs(checkpoints) do
        cp.timer = cp.timer + dt
        if not isActive(cp) and distanceBetween(cp.x, cp.y - 6, player:getX(), player:getY()) < TOUCH_RADIUS then
            activate(cp)
        end
        for i = #cp.sparkles, 1, -1 do
            local s = cp.sparkles[i]
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            s.vy = s.vy + 40 * dt
            s.life = s.life - dt
            if s.life <= 0 then table.remove(cp.sparkles, i) end
        end
    end
end

local function drawCheckpoint(cp)
    local q = getQuads()
    local sheet = sprites.environment.checkpoint
    local active = isActive(cp)
    local x, y = math.floor(cp.x), math.floor(cp.y)
    local bob = math.sin(cp.timer * 2.2) * 1.5
    local pulse = 0.5 + math.sin(cp.timer * 3) * 0.5

    pixelfx.world(function()
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.ellipse("fill", x, y, 8, 2.5)

        -- glow behind the crystal
        love.graphics.setBlendMode("add")
        if active then
            love.graphics.setColor(1, 0.45, 0.1, 0.25 + 0.15 * pulse)
            love.graphics.circle("fill", x, y - 19 + bob, 9 + pulse * 2)
        else
            love.graphics.setColor(0.5, 0.7, 1, 0.08 + 0.06 * pulse)
            love.graphics.circle("fill", x, y - 19 + bob, 7)
        end
    end)

    setWhite()
    love.graphics.draw(sheet, q.base, x - 8, y - 10)
    love.graphics.draw(sheet, active and q.on or q.off, x - 4, y - 27 + bob)

    for _, s in ipairs(cp.sparkles) do
        love.graphics.setColor(1, 0.75, 0.35, math.min(1, s.life * 2))
        love.graphics.rectangle("fill", s.x - 0.75, s.y - 0.75, 1.5, 1.5)
    end
    setWhite()
end

function checkpoints:collect(items)
    for _, cp in ipairs(checkpoints) do
        table.insert(items, { y = cp.y, draw = drawCheckpoint, arg = cp })
    end
end

function checkpoints:drawOverlay()
    if isPlayerFrozen() or pause.active then return end
    for _, cp in ipairs(checkpoints) do
        if distanceBetween(cp.x, cp.y - 6, player:getX(), player:getY()) < TOUCH_RADIUS + 10 then
            local text = "Checkpoint  -  [E] Save" .. (onchain:canSave() and " on-chain" or "")
            if saveState.chainSaving then text = "Saving on-chain..." end
            local sx, sy = cam:cameraCoords(cp.x, cp.y - 32)
            love.graphics.setFont(fonts.small)
            local tw = fonts.small:getWidth(text) + 6 * scale
            local th = fonts.small:getHeight() + 2 * scale
            love.graphics.setColor(0.07, 0.05, 0.06, 0.92)
            love.graphics.rectangle("fill", sx - tw / 2, sy - th, tw, th, scale * 0.6, scale * 0.6)
            love.graphics.setColor(1, 0.42, 0.1, 1)
            love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.5)))
            love.graphics.rectangle("line", sx - tw / 2, sy - th, tw, th, scale * 0.6, scale * 0.6)
            love.graphics.setColor(1, 0.9, 0.75, 1)
            love.graphics.printf(text, sx - tw / 2, sy - th + scale, tw, "center")
            love.graphics.setLineWidth(1)
            setWhite()
        end
    end
end
