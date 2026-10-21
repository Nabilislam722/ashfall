-- The Storm Staff: the player holds it upright at their side. Hold its mouse
-- button to draw mana out of the land around you (glowing motes stream into
-- its head, which glows and crackles with lightning once it is full) while a
-- storm cloud gathers over the spot you aim at (a ring on the ground marks it,
-- snapping onto an enemy near the cursor). Let go and one bolt of lightning
-- falls from the cloud: its blast hurts and stuns everyone around where it
-- lands (hardest at its heart) and scorches the ground. More mana means a
-- harder strike over a wider area. With nobody there it strikes the ground.
-- Elder Mara hands it to players who keep losing to Rick, or to everyone once
-- Rick is beaten. (Saves
-- still know it as data.skills.laserStaff.)
--
-- staff.mana is the player's mana pool, shared by the staff and spells (the
-- F fireball, the Shift+click flame). It refills slowly on its own (REGEN per
-- second, starting a moment after mana was last used) and much faster while
-- the staff is held to draw mana from the land. Releasing the staff spends
-- everything in the pool.
--
-- Mana capacity starts at 100. Once Rick is beaten (the Mana Well wakes up),
-- veHEMI held by the connected wallet raises it, on a log scale so small
-- holders feel it and whales can't break the game:
--   capacity = 100 + min(200, floor(40 * log10(1 + veHEMI)))
--   10 veHEMI +41   100 veHEMI +80   1,000 veHEMI +120   10,000 veHEMI +160   max +200
--
-- The lightning glows on its own: staff:drawEmissive() draws it over the
-- darkness of dungeons, and staff:lights() lights the ground around it.
-- staff:drawGround() draws the scorch marks under everyone's feet.

staff = {}
staff.mana = 100
staff.regenDelay = 0
staff.channeling = false
staff.armed = false   -- the staff's button was pressed this hold
staff.button = nil
staff.showTimer = 0   -- keeps the staff raised briefly after the lightning falls
staff.lift = 0        -- the quick upward thrust as the lightning is called down
staff.aim = nil       -- where the lightning will fall: { x, y (the ground), target }
staff.clouds = {}     -- storm clouds the lightning falls from
staff.bolts = {}      -- lightning on screen
staff.arcs = {}       -- little sparks of static around the crystal while it charges
staff.scorches = {}   -- marks the strikes leave on the ground
staff.motes = {}
staff.sparks = {}
staff.moteTimer = 0
staff.arcTimer = 0
staff.flash = 0
staff.full = false

local BASE_MANA = 100
local MAX_VE_BONUS = 200
local CHARGE_RATE = 70    -- mana per second while channeling
local REGEN = 4           -- mana per second on its own (a little more with a bigger pool)
local REGEN_DELAY = 1.2   -- seconds after using mana before it starts coming back
local MIN_MANA = 20       -- below this it fizzles
local CAST_RANGE = 140    -- how far from the player the lightning can be called down
local SNAP = 40           -- an enemy this close to the aimed spot draws the strike
local AREA = 28           -- the blast catches everyone this far from where it lands...
local AREA_GROWTH = 32    -- ...and this much further on a full charge
local AREA_SQUASH = 0.55  -- it spreads over the floor: drawn (and felt) as a flat ellipse
local EDGE_DAMAGE = 0.5   -- at the blast's edge it hits this hard (full at its heart)
local CLOUD_HEIGHT = 50   -- how high above the ground the storm cloud hangs
local BOLT_LIFE = 0.32
local DAMAGE_BONUS = 2.4  -- strike damage: original, +20%, then doubled
local HUM_PATH = "sounds/items/manaHum.wav"
local BOLT_COLOR = { 0.78, 1, 0.6 } -- pale yellow-green lightning
local CRYSTAL = 23        -- the middle of the staff's head, this far above its foot

local hum = nil

function staff:owned()
    return data.skills.laserStaff == true
end

-- extra mana capacity for a veHEMI balance
function staff.manaBonus(vePower)
    vePower = tonumber(vePower) or 0
    if vePower <= 0 then return 0 end
    return math.min(MAX_VE_BONUS, math.floor(40 * math.log10(1 + vePower)))
end

-- veHEMI of the connected wallet (0 on desktop or without a wallet)
function staff:vePower()
    if not onchain or not onchain:connected() then return 0 end
    return tonumber(onchain.remote.vePower) or 0
end

function staff:maxMana()
    if not (data.story.manaUnlocked or data.story.rickDefeated) then return BASE_MANA end
    return BASE_MANA + staff.manaBonus(self:vePower())
end

-- spells take mana from the pool; regeneration pauses for a moment after
function staff:spend(amount)
    self.mana = math.max(0, self.mana - amount)
    self.regenDelay = REGEN_DELAY
end

-- a fresh journey starts with a full pool
function staff:refill()
    self.mana = self:maxMana()
    self.regenDelay = 0
end

-- the player carries it while it is equipped (put away while rolling, swinging
-- the sword, aiming the bow and so on)
function staff:inHand()
    if not self:owned() or not (data.item.left == "staff" or data.item.right == "staff") then return false end
    if lairStory and lairStory.heroDown then return false end
    return self.channeling or self.showTimer > 0 or (player.state == 0 and not player.aiming)
end

-- the bottom of the staff and its lean: upright at the player's side (on the
-- side they face), raised while it gathers lightning and thrust up as it falls
function staff:hold()
    local side = player.dirX >= 0 and 1 or -1
    local raised = (self.channeling or self.showTimer > 0) and 1 or 0
    local lift = 3 * raised + 4 * self.lift
    local vx, vy = player:getLinearVelocity()
    local step = (raised == 0 and vx * vx + vy * vy > 25) and (math.floor(love.timer.getTime() * 8) % 2) or 0
    return player:getX() + side * 7, player:getY() + 7 - lift + step, side * 0.09 * (1 - raised)
end

-- where the crystal is
function staff:tip()
    local x, y, lean = self:hold()
    return x + math.sin(lean) * CRYSTAL, y - math.cos(lean) * CRYSTAL
end

-- called from useItem when the staff's mouse button goes down
function staff:press(button)
    if not self:owned() or player.state ~= 0 or isPlayerFrozen() or fireballs.charge then return end
    self.armed = true
    self.button = button
end

function staff:startChannel()
    self.channeling = true
    self.full = false
    if not hum then
        hum = love.audio.newSource(HUM_PATH, "static")
        hum:setLooping(true)
    end
    hum:setVolume(0.35)
    hum:setPitch(0.8)
    hum:play()
end

function staff:stopChannel()
    self.channeling = false
    self.armed = false
    self.arcs = {}
    if hum then hum:stop() end
end

function staff:spawnMote()
    local angle = math.random() * math.pi * 2
    local radius = 35 + math.random() * 45
    local colors = { {0.45, 1, 0.9}, {0.6, 1, 0.55}, {0.85, 1, 1} }
    table.insert(self.motes, {
        sx = player:getX() + math.cos(angle) * radius,
        sy = player:getY() + math.sin(angle) * radius * 0.8,
        cx = player:getX() + math.cos(angle + 1.2) * radius * 0.6,
        cy = player:getY() + math.sin(angle + 1.2) * radius * 0.5 - 10,
        t = 0,
        duration = 0.45 + math.random() * 0.3,
        color = colors[math.random(1, #colors)],
    })
end

----------------------------------------------------------------- lightning

-- A jagged path from (x1, y1) to (x2, y2): the line is split in half again and
-- again, each middle pushed sideways a little less than the last, so it wanders
-- the way lightning does. `rough` is how far it may stray, as a share of its length.
local function jagged(x1, y1, x2, y2, rough)
    local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local pts = { x1, y1, x2, y2 }
    local stray = length * rough
    local levels = math.max(2, math.min(5, math.floor(math.log(math.max(4, length) / 3) / math.log(2))))
    for _ = 1, levels do
        local out = { pts[1], pts[2] }
        for i = 1, #pts - 2, 2 do
            local ax, ay, bx, by = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
            local dx, dy = bx - ax, by - ay
            local d = math.max(0.001, math.sqrt(dx * dx + dy * dy))
            local off = (math.random() - 0.5) * stray
            out[#out + 1] = (ax + bx) / 2 - dy / d * off
            out[#out + 1] = (ay + by) / 2 + dx / d * off
            out[#out + 1] = bx
            out[#out + 1] = by
        end
        pts = out
        stray = stray * 0.6
    end
    return pts
end

-- fresh lightning for a bolt (redrawn many times a second, so it flickers):
-- the main path and forks leaping off it
local function crackle(b)
    b.path = jagged(b.x1, b.y1, b.x2, b.y2, 0.3)
    b.forks = {}
    local dx, dy = b.x2 - b.x1, b.y2 - b.y1
    local length = math.sqrt(dx * dx + dy * dy)
    local angle = math.atan2(dy, dx)
    for _ = 1, (length > 30 and 2 or 1) do
        local i = math.random(2, math.max(2, #b.path / 2 - 1)) * 2 - 1
        local fx, fy = b.path[i], b.path[i + 1]
        local a = angle + (math.random() < 0.5 and -1 or 1) * (0.4 + math.random() * 0.6)
        local reach = length * (0.2 + math.random() * 0.25)
        table.insert(b.forks, jagged(fx, fy, fx + math.cos(a) * reach, fy + math.sin(a) * reach, 0.3))
    end
    b.flicker = 0.035
end

-- how far the blast reaches with the staff this full (0..1)
local function areaRadius(fill)
    return AREA + AREA_GROWTH * fill
end

-- where the lightning will fall: the cursor (no further than CAST_RANGE from the
-- player), drawn onto the enemy nearest it if one is close
function staff:findAim()
    local px, py = player:getX(), player:getY()
    local mx, my = cam:mousePosition()
    local dx, dy = mx - px, my - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d > CAST_RANGE then mx, my = px + dx / d * CAST_RANGE, py + dy / d * CAST_RANGE end
    local best, nearest = nil, math.huge
    for _, c in ipairs(enemiesNear(mx, my, SNAP)) do
        local dd = (c.x - mx) ^ 2 + (c.y - my) ^ 2
        if dd < nearest and (c.x - px) ^ 2 + (c.y - py) ^ 2 <= (CAST_RANGE + SNAP) ^ 2 then best, nearest = c, dd end
    end
    if best then return { x = best.x, y = best.y, target = best } end
    return { x = mx, y = my }
end

-- how high a cloud hangs over the ground at y: CLOUD_HEIGHT up, but kept just
-- inside the top of the screen (and never lower than 24 above its spot), so the
-- lightning is always seen falling out of it
local function cloudY(y)
    local _, top = cam:worldCoords(0, 0)
    return math.max(y - CLOUD_HEIGHT, math.min(top + 14, y - 24))
end

-- the storm cloud over the aimed spot: it follows the aim while the staff
-- gathers lightning, darker and bigger as it fills
function staff:updateCloud(dt)
    local fill = math.min(1, self.mana / self:maxMana())
    if self.channeling and self.aim then
        local c = self.cloud
        if not c then
            c = { x = self.aim.x, y = cloudY(self.aim.y), size = 0.5, alpha = 0, flash = 0, life = math.huge, seed = math.random() * 10 }
            self.cloud = c
            table.insert(self.clouds, c)
        end
        local k = math.min(1, dt * 10)
        c.x = c.x + (self.aim.x - c.x) * k
        c.y = c.y + (cloudY(self.aim.y) - c.y) * k
        c.groundY = self.aim.y
        c.size = 0.55 + 0.45 * fill
        c.alpha = c.alpha + (0.35 + 0.65 * fill - c.alpha) * math.min(1, dt * 6)
        c.fill = fill
    end
    for i = #self.clouds, 1, -1 do
        local c = self.clouds[i]
        c.flash = math.max(0, c.flash - dt * 4)
        if c.life ~= math.huge then
            c.life = c.life - dt
            c.alpha = math.max(0, math.min(1, c.alpha + dt * 8, c.life / 0.5))
            if c.life <= 0 then table.remove(self.clouds, i) end
        end
    end
end

function staff:fire()
    local mana = self.mana
    local aim = self.aim or self:findAim()
    self.showTimer = 0.45
    player:setDirFromVector(vector(aim.x - player:getX(), aim.y - player:getY()):normalized())

    local cloud = self.cloud
    self.cloud = nil
    if mana < MIN_MANA then
        -- too little to call the lightning: nothing is spent, the cloud melts away
        local tx, ty = self:tip()
        for _ = 1, 6 do
            table.insert(self.sparks, { x = tx, y = ty, vx = (math.random() - 0.5) * 40, vy = -math.random() * 30, life = 0.35, color = {0.5, 0.6, 0.65} })
        end
        if cloud then cloud.life = 0.4 end
        dj.play("sounds/items/fizzle.wav", "static", "effect", 0.9)
        return
    end

    self:spend(mana)
    local power = math.min(1, mana / self:maxMana())
    self.lift = 1
    self.motes = {} -- the mana gathered is spent: what was still flowing in is gone

    -- one bolt, out of the cloud that gathered, onto the target (or the ground)
    if cloud then cloud.life = 0.7 end
    self:strike({ x = aim.x, y = aim.y, target = aim.target and aim.target.e, cloud = cloud,
        damage = (1 + mana / 25) * DAMAGE_BONUS, power = power, radius = areaRadius(power) })

    shake:start(0.15 + power * 0.15, 2 + power * 2, 0.02)
    dj.play("sounds/items/stormBolt.wav", "static", "effect", 0.75 + 0.25 * power, 1.12 - power * 0.22)
end

-- the strike lands: lightning falls from the cloud above, the blast hurts and
-- stuns everyone in its area (hardest at its heart), and the ground is scorched
function staff:strike(s)
    local gx, gy = s.x, s.y
    local hy = gy + (s.target and s.target.strikeOffset or -4) -- the body it hits (Gula floats high)
    local cloud = s.cloud
    if not cloud then
        cloud = { x = gx, y = cloudY(gy), groundY = gy, size = 0.75, alpha = 0, flash = 0, life = 0.7, seed = math.random() * 10, fill = 1 }
        table.insert(self.clouds, cloud)
    end
    cloud.flash = 1
    local b = { x1 = cloud.x + (math.random() - 0.5) * 10, y1 = cloud.y + 4, x2 = gx, y2 = hy, gx = gx, gy = gy,
        life = BOLT_LIFE, maxLife = BOLT_LIFE, width = 1 + s.power * 0.8, radius = s.radius }
    crackle(b)
    table.insert(self.bolts, b)
    table.insert(self.scorches, { x = gx, y = gy, t = 0, size = s.radius / 24 })

    for _, c in ipairs(enemiesNear(gx, gy, s.radius)) do
        local dx, dy = c.x - gx, (c.y - gy) / AREA_SQUASH
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= s.radius or c.e == s.target then
            -- knocked out from the heart of the blast (the one struck square: away from the player)
            local away = d > 1 and vector(c.x - gx, c.y - gy):normalized() or vector(gx - player:getX(), gy - player:getY() + 0.01):normalized()
            c.e:hit(s.damage * (1 - (1 - EDGE_DAMAGE) * math.min(1, d / s.radius)), away, 0.3)
            for _ = 1, 5 do
                local a = math.random() * math.pi * 2
                table.insert(self.sparks, { x = c.x, y = c.y - 4, vx = math.cos(a) * 40, vy = math.sin(a) * 25 - 15,
                    life = 0.15 + math.random() * 0.2, color = {0.88, 1, 0.7} })
            end
        end
    end
    self.flash = math.max(self.flash, 0.3 + 0.5 * s.power)
    for _ = 1, 14 + math.floor(10 * s.power) do
        local a = math.random() * math.pi * 2
        local speed = 30 + math.random() * (40 + s.radius)
        table.insert(self.sparks, {
            x = gx, y = hy, vx = math.cos(a) * speed, vy = math.sin(a) * speed * 0.6 - 20,
            life = 0.2 + math.random() * 0.25, color = math.random() < 0.5 and {1, 1, 1} or {0.88, 1, 0.7},
        })
    end
end

-- static around the crystal while it charges: more, and longer, as it fills
function staff:updateArcs(dt)
    for i = #self.arcs, 1, -1 do
        local a = self.arcs[i]
        a.life = a.life - dt
        if a.life <= 0 then table.remove(self.arcs, i) end
    end
    if not (self.channeling and self.full) then return end -- only once it is fully charged
    self.arcTimer = self.arcTimer - dt
    while self.arcTimer <= 0 do
        self.arcTimer = self.arcTimer + 0.05
        local angle = -math.pi / 2 + (math.random() - 0.5) * 2.4 -- crackling up off the head
        local reach = 4 + math.random() * 8
        -- (drawn from the crystal, wherever it is by then)
        table.insert(self.arcs, { path = jagged(0, 0, math.cos(angle) * reach, math.sin(angle) * reach, 0.45), life = 0.05 + math.random() * 0.06 })
    end
end

function staff:update(dt)
    if self.showTimer > 0 then self.showTimer = self.showTimer - dt end
    if self.flash > 0 then self.flash = math.max(0, self.flash - dt * 5) end
    if self.lift > 0 then self.lift = math.max(0, self.lift - dt * 4) end

    -- channel while the staff's button is held
    local held = self.armed and self.button and love.mouse.isDown(self.button == "left" and 1 or 2)
    if held and not isPlayerFrozen() and not pause.active and player.state == 0 then
        if not self.channeling then self:startChannel() end
        -- a bigger well also fills a little faster, so full charges stay snappy
        local maxMana = self:maxMana()
        local rate = CHARGE_RATE * math.sqrt(maxMana / BASE_MANA)
        self.mana = math.min(maxMana, self.mana + rate * dt)
        self.aim = self:findAim()
        player:setDirFromVector(toMouseVector(player:getX(), player:getY()))
        if hum then hum:setPitch(0.8 + 0.6 * self.mana / maxMana) end
        if self.mana >= maxMana and not self.full then
            self.full = true
            dj.play("sounds/items/manaFull.wav", "static", "effect", 0.8)
        end
        self.moteTimer = self.moteTimer - dt
        while self.moteTimer <= 0 do
            self.moteTimer = self.moteTimer + (self.full and 0.08 or 0.03)
            self:spawnMote()
        end
    elseif self.channeling then
        self:stopChannel()
        -- released: call the lightning down. Knocked back mid-charge: keep the mana for later
        if not isPlayerFrozen() and player.state == 0 then
            self:fire()
        elseif self.cloud then
            self.cloud.life = 0.4
            self.cloud = nil
        end
        self.aim = nil
    else
        self.armed = false
        -- the pool refills slowly on its own
        local maxMana = self:maxMana()
        if self.regenDelay > 0 then
            self.regenDelay = self.regenDelay - dt
        elseif self.mana < maxMana then
            self.mana = math.min(maxMana, self.mana + REGEN * math.sqrt(maxMana / BASE_MANA) * dt)
        end
    end
    -- a smaller pool (veHEMI unlocking, wallet disconnected) can't hold more
    self.mana = math.min(self.mana, self:maxMana())
    self:updateArcs(dt)
    self:updateCloud(dt)

    for i = #self.bolts, 1, -1 do
        local b = self.bolts[i]
        b.life = b.life - dt
        b.flicker = b.flicker - dt
        if b.life <= 0 then
            table.remove(self.bolts, i)
        elseif b.flicker <= 0 then
            crackle(b)
        end
    end
    for i = #self.scorches, 1, -1 do
        local s = self.scorches[i]
        s.t = s.t + dt
        if s.t > 2.5 then table.remove(self.scorches, i) end
    end
    for i = #self.motes, 1, -1 do
        local m = self.motes[i]
        m.t = m.t + dt / m.duration
        if m.t >= 1 then table.remove(self.motes, i) end
    end
    for i = #self.sparks, 1, -1 do
        local s = self.sparks[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        s.vx, s.vy = s.vx * 0.9, s.vy * 0.9
        s.life = s.life - dt
        if s.life <= 0 then table.remove(self.sparks, i) end
    end
end

-- leaving a map: stop channeling (the mana pool carries over)
function staff:reset()
    self:stopChannel()
    self.motes, self.bolts, self.arcs, self.sparks = {}, {}, {}, {}
    self.clouds, self.scorches, self.cloud, self.aim = {}, {}, nil, nil
    self.flash, self.lift = 0, 0
end

-- the light the lightning (and the charging crystal) throws on the ground
function staff:lights(list)
    for _, b in ipairs(self.bolts) do
        local f = b.life / b.maxLife
        table.insert(list, { x = b.gx, y = b.gy, radius = b.radius + 30 + 50 * f, color = BOLT_COLOR, strength = f })
        table.insert(list, { x = (b.x1 + b.x2) / 2, y = (b.y1 + b.y2) / 2, radius = 40, color = BOLT_COLOR, strength = 0.6 * f })
    end
    if self.channeling and self.full then
        local tx, ty = self:tip()
        table.insert(list, { x = tx, y = ty, radius = 36, color = BOLT_COLOR, strength = 0.7 })
    end
end

-- the staff in the player's hand: upright at their side, its head glowing
-- once it is fully charged (drawn with the player)
function staff:drawHeld()
    if not self:inHand() then return end
    local img = sprites.items.staff
    local x, y, lean = self:hold()
    setWhite()
    love.graphics.draw(img, x, y, lean, 1, 1, img:getWidth() / 2, img:getHeight() - 1)
    if self.channeling and self.full then
        local tx, ty = self:tip()
        local pulse = math.sin(love.timer.getTime() * 20)
        pixelfx.world(function()
            love.graphics.setBlendMode("add")
            love.graphics.setColor(BOLT_COLOR[1], BOLT_COLOR[2], BOLT_COLOR[3], 0.35)
            love.graphics.circle("fill", tx, ty, 6 + pulse)
            love.graphics.setColor(0.93, 1, 0.8, 0.8)
            love.graphics.circle("fill", tx, ty, 2.5 + 0.5 * pulse)
        end)
        setWhite()
    end
end

-- scorch marks the strikes leave, under everyone's feet
function staff:drawGround()
    if #self.scorches == 0 then return end
    pixelfx.world(function()
        for _, s in ipairs(self.scorches) do
            local fade = 1 - s.t / 2.5
            love.graphics.setColor(0.06, 0.06, 0.1, 0.45 * fade)
            love.graphics.ellipse("fill", s.x, s.y, 9 * s.size, 4.5 * s.size)
            love.graphics.setColor(0.02, 0.02, 0.05, 0.5 * fade)
            love.graphics.ellipse("fill", s.x, s.y, 4.5 * s.size, 2.2 * s.size)
        end
    end)
    setWhite()
end

-- a storm cloud: dark puffs with a dark outline and lighter tops, lit from
-- inside when lightning gathers or falls (drawn as pixel art)
local PUFFS = { { 0, 0, 9 }, { -9, 2, 7 }, { 9, 2, 7 }, { -4, -5, 7 }, { 5, -4, 6 }, { -14, 4, 5 }, { 14, 5, 5 } }

local function drawCloud(c)
    if c.alpha <= 0.01 then return end
    local s = c.size
    -- its shadow on the ground below
    love.graphics.setColor(0, 0, 0, 0.12 * c.alpha)
    love.graphics.ellipse("fill", c.x, c.groundY or (c.y + CLOUD_HEIGHT), 18 * s, 6 * s)
    local t = love.timer.getTime()
    for i, p in ipairs(PUFFS) do
        local wob = math.sin(t * 2 + i + c.seed) * 0.8
        love.graphics.setColor(0.06, 0.07, 0.11, c.alpha)
        love.graphics.circle("fill", c.x + p[1] * s, c.y + p[2] * s + wob, p[3] * s + 1)
    end
    for i, p in ipairs(PUFFS) do
        local wob = math.sin(t * 2 + i + c.seed) * 0.8
        love.graphics.setColor(0.2, 0.22, 0.3, c.alpha)
        love.graphics.circle("fill", c.x + p[1] * s, c.y + p[2] * s + wob, p[3] * s)
    end
    for i, p in ipairs(PUFFS) do
        local wob = math.sin(t * 2 + i + c.seed) * 0.8
        love.graphics.setColor(0.36, 0.39, 0.5, c.alpha)
        love.graphics.circle("fill", c.x + p[1] * s - 1, c.y + p[2] * s + wob - 1.5, p[3] * s * 0.6)
    end
end

-- the mana swirl and motes, the storm clouds, and the ring on the ground where
-- the lightning will fall: drawn above the world
function staff:draw()
    if #self.clouds == 0 and not self.channeling and #self.motes == 0 then return end
    pixelfx.world(function() self:drawAir() end)
end

function staff:drawAir()
    for _, c in ipairs(self.clouds) do drawCloud(c) end

    love.graphics.setBlendMode("add")
    if self.channeling then
        local t = love.timer.getTime()
        local fill = math.min(1, self.mana / self:maxMana())
        -- swirl around the player while drawing mana
        local radius = 30 - fill * 12
        love.graphics.setLineWidth(1)
        for i = 0, 2 do
            local a = t * 3 + i * math.pi * 2 / 3
            love.graphics.setColor(0.4, 1, 0.85, 0.25)
            love.graphics.arc("line", "open", player:getX(), player:getY(), radius, a, a + 1.2)
        end
        -- the target ring: it tightens as the lightning gathers
        if self.aim then
            local ax, ay = self.aim.x, self.aim.y + (self.aim.target and 3 or 0)
            local r = 15 - 6 * fill
            local locked = self.aim.target ~= nil
            love.graphics.setColor(locked and 0.9 or 0.75, 1, locked and 0.7 or 0.6, 0.55 + 0.35 * fill)
            love.graphics.ellipse("line", ax, ay, r, r * 0.55)
            for k = 0, 3 do
                local a = k * math.pi / 2 + t * 2
                local c, s = math.cos(a), math.sin(a)
                love.graphics.line(ax + c * (r + 1.5), ay + s * (r + 1.5) * 0.55, ax + c * (r + 4.5), ay + s * (r + 4.5) * 0.55)
            end
        end
    end

    local tx, ty = self:tip()
    for _, m in ipairs(self.motes) do
        -- quadratic curve from the land into the crystal
        local t = m.t * m.t
        local u = 1 - t
        local x = u * u * m.sx + 2 * u * t * m.cx + t * t * tx
        local y = u * u * m.sy + 2 * u * t * m.cy + t * t * ty
        local alpha = math.min(1, (1 - m.t) * 3, m.t * 6)
        love.graphics.setColor(m.color[1], m.color[2], m.color[3], 0.3 * alpha)
        love.graphics.circle("fill", x, y, 2.5)
        love.graphics.setColor(m.color[1], m.color[2], m.color[3], alpha)
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
    end

    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
    setWhite()
end

-- one line of lightning: a coloured glow, then a bright body, then a white core
local function drawLightning(path, width, alpha)
    love.graphics.setLineWidth(width * 3.2)
    love.graphics.setColor(BOLT_COLOR[1] * 0.8, BOLT_COLOR[2] * 0.9, BOLT_COLOR[3] * 0.7, 0.3 * alpha)
    love.graphics.line(path)
    love.graphics.setLineWidth(width * 1.5)
    love.graphics.setColor(0.93, 1, 0.8, 0.85 * alpha)
    love.graphics.line(path)
    love.graphics.setLineWidth(math.max(0.35, width * 0.6))
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.line(path)
end

-- the lightning, the flicker inside the clouds, sparks and the crackle around the
-- crystal: they glow on their own, so they are drawn after (over) the darkness
-- of a dungeon
function staff:drawEmissive()
    if #self.bolts == 0 and #self.sparks == 0 and #self.arcs == 0 and #self.clouds == 0 and self.flash <= 0 then return end
    cam:attach()
    pixelfx.world(function() self:drawGlowing() end)
    cam:detach()

    -- a strike lights the whole screen for an instant
    if self.flash > 0 then
        love.graphics.push("all")
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.8, 1, 0.65, 0.16 * self.flash)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.pop()
    end
end

function staff:drawGlowing()
    love.graphics.setBlendMode("add")
    love.graphics.setLineJoin("bevel")

    if #self.arcs > 0 then
        local tx, ty = self:tip()
        love.graphics.push()
        love.graphics.translate(tx, ty)
        for _, a in ipairs(self.arcs) do drawLightning(a.path, 0.35, 0.9) end
        love.graphics.pop()
    end

    -- lightning stirring inside the clouds (more as the staff fills), and the
    -- flash as a strike leaves them
    for _, c in ipairs(self.clouds) do
        local stir = (c.fill or 1) * 0.5
        if c.alpha > 0.05 and math.random() < 0.08 + 0.25 * stir then
            local x = c.x + (math.random() - 0.5) * 20 * c.size
            love.graphics.setColor(BOLT_COLOR[1], BOLT_COLOR[2], BOLT_COLOR[3], 0.25 * c.alpha)
            love.graphics.circle("fill", x, c.y + (math.random() - 0.5) * 6, 5 + math.random() * 5)
        end
        if c.flash > 0 then
            love.graphics.setColor(0.88, 1, 0.75, 0.4 * c.flash * c.alpha)
            for _, p in ipairs(PUFFS) do love.graphics.circle("fill", c.x + p[1] * c.size, c.y + p[2] * c.size, p[3] * c.size) end
        end
    end

    for _, b in ipairs(self.bolts) do
        local fade = b.life / b.maxLife
        -- it lands white-hot and thick, then thins as it dies
        local hot = math.max(0, (b.life - (b.maxLife - 0.07)) / 0.07)
        local alpha = math.min(1, fade * 1.6)
        if hot > 0 then
            -- a column of light down the strike, for an instant
            love.graphics.setColor(0.8, 1, 0.65, 0.22 * hot)
            love.graphics.rectangle("fill", b.x2 - 5, b.y1, 10, b.y2 - b.y1)
        end
        drawLightning(b.path, b.width * (0.7 + 0.7 * hot + 0.3 * fade), alpha)
        for _, f in ipairs(b.forks) do drawLightning(f, b.width * 0.55, alpha * 0.8) end
        -- where it lands: a white burst, the whole blast lit up for a moment, and
        -- a ring of light racing out to its edge
        love.graphics.setColor(BOLT_COLOR[1], BOLT_COLOR[2], BOLT_COLOR[3], 0.4 * fade)
        love.graphics.circle("fill", b.x2, b.y2, 5 + 8 * fade)
        love.graphics.setColor(1, 1, 1, fade)
        love.graphics.circle("fill", b.x2, b.y2, 1.5 + 3 * fade)
        love.graphics.setColor(0.8, 1, 0.65, 0.22 * fade * fade)
        love.graphics.ellipse("fill", b.gx, b.gy, b.radius, b.radius * AREA_SQUASH)
        local ring = 4 + (b.radius - 4) * (1 - fade ^ 3)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.9, 1, 0.75, 0.85 * fade)
        love.graphics.ellipse("line", b.gx, b.gy, ring, ring * AREA_SQUASH)
    end

    for _, s in ipairs(self.sparks) do
        love.graphics.setColor(s.color[1], s.color[2], s.color[3], math.min(1, s.life * 4))
        love.graphics.rectangle("fill", math.floor(s.x), math.floor(s.y), 1, 1)
    end
end
