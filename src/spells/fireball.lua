-- Fireball: the basic spell. Tap its key (KEY, E for now) to hurl one toward the cursor; it costs
-- mana from the player's pool (staff.mana), which refills slowly on its own.
-- A direct hit deals 3 damage and sets the target alight; the burst splashes
-- 1 damage onto anything else close by.
--
-- Hold it to charge it: the ball forms in the hero's hand and swells, drawing
-- embers in, and burns more mana every moment it grows (CHARGE_DRAIN a second).
-- Let go and it flies bigger, heavier and slower, hits much harder and bursts
-- wider; a full charge sets everything in the blast alight. Out of mana, the
-- charge stops growing; rolled out of, or knocked down by a boss, it fizzles.

fireballs = {}
fireballs.KEY = "e"            -- the key that casts it (main.lua: E talks to anyone close by first)
fireballs.COST = 20
fireballs.COOLDOWN = 0.35
fireballs.CHARGE_DELAY = 0.15  -- held longer than this, it starts to charge (a tap is a plain fireball)
fireballs.CHARGE_TIME = 1.4    -- from a plain fireball to a full charge
fireballs.CHARGE_DRAIN = 32    -- mana a second while it grows
fireballs.charge = nil         -- the ball in the hero's hand, while its key is held

local FRAME_TIME = 0.07 -- its flames flicker through the sheet's 4 frames
local HUM_PATH = "sounds/items/manaHum.wav"

local cooldown = 0
local hum = nil

-- what a ball of power p does: 0 a plain fireball, 1 a full charge
local function stats(p)
    local half = function(v) return math.floor(v * 2 + 0.5) / 2 end
    return {
        direct = half(3 + 5 * p),     -- 3 .. 8
        splash = half(1 + 2 * p),     -- 1 .. 3
        radius = 18 + 22 * p,         -- the blast, 18 .. 40 px
        size = 1 + 1.1 * p,           -- drawn 1 .. 2.1 times as big
        speed = 175 - 35 * p,         -- heavier, slower
        rad = 4 + 5 * p,              -- its body
        knock = 0.12 + 0.18 * p,
        life = 1.6 + 0.4 * p,
    }
end
fireballs.stats = stats

-- the sheets point right (fireball) and up-right (fireballDiagonal): one of the
-- two, turned a whole quarter at a time, faces each of the 8 ways crisply
local function facing(rot)
    local k = math.floor(rot / (math.pi / 4) + 0.5)
    if k % 2 == 0 then return "fireball", k / 2 * math.pi / 2 end
    return "fireballDiagonal", (k + 1) / 2 * math.pi / 2
end

local function burst(x, y, p)
    for _ = 1, math.floor(10 + 20 * p) do
        effects:spawn("ember", x, y, { scale = 1 + 0.6 * p })
    end
    effects:spawn("fireballSmoke", x, y, { scale = 1.1 + p })
    effects:spawn("fireballBurst", x, y, { scale = 1 + 1.1 * p, slow = 1 + 0.5 * p })
    if p > 0.4 then effects:spawn("scorch", x, y) end
    shake:start(0.08 + 0.12 * p, 1.2 + 2.3 * p, 0.02)
    dj.play(sounds.items.fire, "static", "effect", 0.7 + 0.3 * p, 1.3 - 0.5 * p)
    if p >= 0.75 then dj.play(sounds.items.explosion, "static", "effect", 0.6, 1.1) end
end

local function explode(ball, directHit)
    ball.dead = true
    local s = ball.stats
    burst(ball.x, ball.y, ball.power)
    if directHit then
        directHit:hit(s.direct, ball.dirVec, s.knock)
        if directHit.burn then directHit:burn() end
    end
    for _, collider in ipairs(world:queryCircleArea(ball.x, ball.y, s.radius, { 'Enemy' })) do
        local target = collider.parent
        if target and target ~= directHit then
            local tx, ty = collider:getPosition()
            local away = vector(tx - ball.x, ty - ball.y)
            if away:len() < 0.01 then away = ball.dirVec end
            target:hit(s.splash, away:normalized(), 0.08 + 0.1 * ball.power)
            -- a full charge sets the whole blast alight
            if ball.power >= 0.999 and target.burn then target:burn() end
        end
    end
end

-- a fireball of power p (0 plain .. 1 fully charged) from x, y toward the cursor
function spawnFire(x, y, p)
    p = p or 0
    local direction = toMouseVector(x, y)
    local s = stats(p)

    local fireball = {}
    fireball.x = x
    fireball.y = y
    fireball.power = p
    fireball.stats = s
    fireball.timer = s.life
    fireball.age = 0
    fireball.emberTimer = 0
    fireball.dead = false
    fireball.dir = direction
    fireball.dirVec = direction
    fireball.rot = math.atan2(direction.y, direction.x)
    fireball.rad = s.rad
    fireball.speed = s.speed

    function fireball:update(dt)
        self.age = self.age + dt
        self.timer = self.timer - dt
        if self.timer < 0 then
            explode(self)
            return
        end

        -- a trail of smoke and embers, thicker the stronger it is
        self.emberTimer = self.emberTimer - dt
        if self.emberTimer < 0 then
            effects:spawn("fireballSmoke", self.x, self.y, {scale = 0.8 + 0.7 * self.power})
            for _ = 1, 2 + math.floor(3 * self.power) do
                effects:spawn("ember", self.x + (math.random() - 0.5) * 6 * self.power, self.y + (math.random() - 0.5) * 6 * self.power,
                    {scale = 0.85 + 0.5 * self.power})
            end
            self.emberTimer = 0.025
        end

        self.x = self.x + (self.dirVec.x * self.speed * dt)
        self.y = self.y + (self.dirVec.y * self.speed * dt)

        if #world:queryCircleArea(self.x, self.y, self.rad, {'Wall'}) > 0 then
            explode(self)
            return
        end

        local hitEnemies = world:queryCircleArea(self.x, self.y, self.rad, {'Enemy'})
        if #hitEnemies > 0 and hitEnemies[1].parent then
            explode(self, hitEnemies[1].parent)
        end
    end

    table.insert(fireballs, fireball)
    return fireball
end

-- ---------------------------------------------------------------- the charge
local function startHum()
    if not hum then
        hum = love.audio.newSource(HUM_PATH, "static")
        hum:setLooping(true)
    end
    hum:setVolume(0.3)
    hum:setPitch(0.6)
    hum:play()
end

local function stopHum()
    if hum then hum:stop() end
end

-- where the ball hovers: in front of the hero, toward the cursor, a little raised
local function handPos(c)
    local reach = 8 + 4 * c.power
    local bob = math.sin(love.timer.getTime() * 5) * 0.6
    return player:getX() + c.dir.x * reach, player:getY() - 3 + c.dir.y * reach * 0.8 + bob
end

local function launch(c)
    cooldown = fireballs.COOLDOWN
    local p = c.power
    local dir = toMouseVector(player:getX(), player:getY() - 2)
    player:setDirFromVector(dir)
    player:useItem(0.2 + 0.1 * p)
    player:useSet()
    spawnFire(player:getX() + dir.x * 6, player:getY() - 2 + dir.y * 6, p)
    dj.play(sounds.items.fire, "static", "effect", 0.8 + 0.2 * p, 1.1 - 0.35 * p)
    if p > 0.5 then shake:start(0.06, 0.6 + p, 0.02) end
end

-- the ball breaks up in the hero's hand (the mana spent on it is gone)
local function fizzle(c)
    local x, y = handPos(c)
    for _ = 1, 3 + math.floor(5 * c.power) do
        effects:spawn("fireballSmoke", x + (math.random() - 0.5) * 6, y + (math.random() - 0.5) * 6, { scale = 0.5 + 0.6 * c.power })
    end
    dj.play("sounds/items/fizzle.wav", "static", "effect", 0.8)
end

-- F pressed: pay for the ball and hold it (released quickly, it's a plain fireball)
function fireballs:press()
    if cooldown > 0 or self.charge or isPlayerFrozen() or pause.active or player.state ~= 0 or staff.channeling then
        return false
    end
    if staff.mana < self.COST then
        player:outOfAmmo("Not enough mana!")
        return false
    end
    staff:spend(self.COST)
    self.charge = { held = 0, power = 0, charging = false, full = false, flash = 0, dry = false, sparks = {}, sparkTimer = 0,
        dir = toMouseVector(player:getX(), player:getY() - 2) }
    return true
end

-- is the hero charging one (it slows them down, as the staff's charge does)
function fireballs:charging()
    return self.charge ~= nil and self.charge.charging
end

local function spark(c)
    local a = math.random() * math.pi * 2
    table.insert(c.sparks, { a = a, r = 12 + math.random() * 12 + 10 * c.power, spin = (math.random() < 0.5 and -1 or 1) * (2 + math.random() * 2),
        size = math.random() < 0.3 + 0.4 * c.power and 2 or 1, hot = math.random() })
end

function fireballs:updateCharge(dt)
    local c = self.charge
    if not c then return end
    c.flash = math.max(0, c.flash - dt * 3)
    -- rolled out of, frozen, knocked down: it fizzles
    if isPlayerFrozen() or pause.active or player.state ~= 0 then
        self.charge = nil
        stopHum()
        fizzle(c)
        return
    end
    c.dir = toMouseVector(player:getX(), player:getY() - 2)
    -- let go: it flies
    if not love.keyboard.isDown(self.KEY) then
        self.charge = nil
        stopHum()
        launch(c)
        return
    end
    c.held = c.held + dt
    if c.held < self.CHARGE_DELAY then return end

    -- held: it grows, burning mana as it does
    if not c.charging then
        c.charging = true
        startHum()
    end
    player:setDirFromVector(c.dir)
    if c.power < 1 then
        local need = self.CHARGE_DRAIN * dt
        if staff.mana >= need then
            staff:spend(need)
            c.dry = false
            c.power = math.min(1, c.power + dt / self.CHARGE_TIME)
            if c.power >= 1 then
                c.full = true
                c.flash = 1
                dj.play("sounds/items/manaFull.wav", "static", "effect", 0.8, 1.15)
                local x, y = handPos(c)
                for _ = 1, 8 do effects:spawn("ember", x, y, { scale = 1.2 }) end
            end
        elseif not c.dry then
            c.dry = true
            player:outOfAmmo("Out of mana!")
        end
    else
        staff:spend(0) -- held at full: the pool doesn't refill meanwhile
    end
    if hum then hum:setPitch(0.6 + 0.7 * c.power) end

    -- embers drawn in, faster and thicker as it fills
    c.sparkTimer = c.sparkTimer - dt
    while c.sparkTimer <= 0 do
        c.sparkTimer = c.sparkTimer + (c.dry and 0.12 or (0.05 - 0.03 * c.power))
        spark(c)
    end
    for i = #c.sparks, 1, -1 do
        local s = c.sparks[i]
        s.r = s.r - (28 + 40 * c.power) * dt
        s.a = s.a + s.spin * dt
        if s.r < 2 then table.remove(c.sparks, i) end
    end
end

function fireballs:update(dt)
    if cooldown > 0 then cooldown = cooldown - dt end
    self:updateCharge(dt)
    for _,b in ipairs(fireballs) do
        b:update(dt)
    end

    local i = #fireballs
    while i > 0 do
        if fireballs[i].dead then
            table.remove(fireballs, i)
        end
        i = i - 1
    end
end

-- the ball in the hero's hand, in pixels like the art: a spark that swells
-- into a ball of fire (orange, a yellow heart, a white-hot core) with flames
-- licking off it, its heat around it and embers spiralling in, flickering
-- faster as it fills; a flash when it's full, then a ring of heat
local function drawCharge(c)
    local x, y = handPos(c)
    local p = c.power
    local t = love.timer.getTime()
    local flick = math.sin(t * (10 + 16 * p))
    local r = c.charging and (2 + 5 * p) or 1.5
    local dim = c.dry and 0.7 or 1
    pixelfx.world(function()
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 0.42 + 0.25 * p, 0.12, (0.18 + 0.3 * p) * dim)
        love.graphics.circle("fill", x, y, r + 3 + 6 * p + flick * 0.8)
        for _, sp in ipairs(c.sparks) do
            local sx, sy = x + math.cos(sp.a) * sp.r, y + math.sin(sp.a) * sp.r * 0.75
            local near = 1 - math.min(1, sp.r / 24)
            love.graphics.setColor(1, 0.55 + 0.4 * sp.hot * near, 0.2 + 0.4 * near, 0.55 + 0.45 * near)
            love.graphics.rectangle("fill", sx, sy, sp.size, sp.size)
        end
        if c.flash > 0 then
            love.graphics.setColor(1, 0.95, 0.75, 0.8 * c.flash)
            love.graphics.circle("fill", x, y, r + 2 + 16 * (1 - c.flash))
        end
        love.graphics.setBlendMode("alpha")
        if c.full then
            local ring = (t * 1.6) % 1
            love.graphics.setColor(1, 0.6, 0.2, 0.7 * (1 - ring))
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", x, y, r + 3 + 9 * ring)
        end
        -- flames licking up off it
        for i = 1, 2 + math.floor(3 * p) do
            local a = t * 7 + i * 2.1
            local fx = x + math.cos(a) * r * 0.6
            local fy = y - r * 0.55 - (1 + math.sin(a * 1.7)) * (0.8 + 1.8 * p)
            love.graphics.setColor(1, 0.5, 0.12, 0.95 * dim)
            love.graphics.circle("fill", fx, fy, math.max(0.8, r * 0.32))
        end
        -- the ball: white-hot and flickering once it's full
        local hot = c.full and math.floor(t * 8) % 2 == 0
        love.graphics.setColor(0.93, 0.33, 0.1, dim)
        love.graphics.circle("fill", x, y, r + 0.4 * flick)
        love.graphics.setColor(1, hot and 0.92 or 0.72, hot and 0.6 or 0.22, dim)
        love.graphics.circle("fill", x - r * 0.15, y - r * 0.15, r * 0.65)
        love.graphics.setColor(1, 0.98, 0.85, dim)
        love.graphics.circle("fill", x - r * 0.25, y - r * 0.25, math.max(0.8, r * 0.3))
    end)
    love.graphics.setColor(1, 1, 1, 1)
end

function fireballs:draw(layer)
    for _,a in ipairs(fireballs) do
        if (layer == -1 and a.y < player:getY() or (layer == 1 and a.y >= player:getY())) then
            local name, turn = facing(a.rot)
            local frame = math.floor(a.age / FRAME_TIME) % 4 + 1
            local size = a.stats.size
            if a.power > 0 then
                -- a charged one burns with a halo of heat
                pixelfx.world(function()
                    love.graphics.setBlendMode("add")
                    love.graphics.setColor(1, 0.45, 0.15, 0.25 + 0.25 * a.power)
                    love.graphics.circle("fill", a.x, a.y, 3 + 8 * a.power + math.sin(a.age * 30))
                    love.graphics.setBlendMode("alpha")
                end)
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.draw(sprites.effects.magic[name], sprites.effects.magicQuads[name][frame], a.x, a.y, turn, size, size, 36, 36)
        end
    end
    -- the ball being charged: in front of the hero, unless it's held up behind them
    local c = self.charge
    if c then
        local behind = c.dir.y < -0.35
        if (layer == -1 and behind) or (layer == 1 and not behind) then drawCharge(c) end
    end
end

-- the light fireballs throw at night (src/levels/lighting.lua), bigger the stronger they are
function fireballs:lights(list)
    for _, f in ipairs(fireballs) do
        table.insert(list, { x = f.x, y = f.y, radius = 34 + 30 * f.power, color = { 1, 0.55, 0.2 }, strength = 0.9 })
    end
    local c = self.charge
    if c and c.charging then
        local x, y = handPos(c)
        table.insert(list, { x = x, y = y, radius = 16 + 34 * c.power, color = { 1, 0.5, 0.18 }, strength = 0.6 + 0.35 * c.power })
    end
end
