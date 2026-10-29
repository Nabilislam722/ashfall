-- Combat timing: sword clashes, perfect dodges, counters, and the glints that
-- warn of a blow.
--
-- Clash. A swing of the hero's sword parries for a moment (PARRY_WINDOW from
-- the click). A blow that can be parried (combat:melee: a blade, a bite, a
-- sword wave) that meets the swing in that moment, coming from in front of the
-- hero, clashes: sparks, a clang, a heartbeat's hitstop, and neither side is
-- hurt. The hero is pushed back a step and the attacker reels (attacker:onClash).
-- It works the other way round too: the hero's sword landing on a monster in
-- the middle of its strike (monster:striking()) clashes instead of cutting.
--
-- Perfect dodge. Rolling, dodging or Shadow Stepping through a blow that would
-- have landed, within PERFECT_WINDOW of starting the move: whoever threw the
-- blow is slowed almost to a stop for SLOWED_TIME (it moves, swings and
-- animates at SLOWED_SCALE), some stamina comes back, and the hero is left in a
-- ring of afterimages. Monsters and bosses run their frames between
-- combat:slowIn and combat:slowOut for this.
--
-- Counter. The hero's next cut after a clash or a perfect dodge (within
-- COUNTER_TIME), and every cut on a monster still slowed by a perfect dodge,
-- does COUNTER_BONUS times the damage.
--
-- Glints. A monster winding up a blow flashes a star on it just before it comes:
-- white ("parry") can be clashed, red ("dodge") can only be dodged.
-- Blows that can't be parried at all go through combat:unblockable.

combat = {}
combat.PARRY_WINDOW = 0.22
combat.PERFECT_WINDOW = 0.25
combat.COUNTER_TIME = 1.5
combat.COUNTER_BONUS = 3

local PARRY_REACH = 46                    -- the blow must come from this close...
local PARRY_ARC = math.cos(math.rad(80))  -- ...and within 80 degrees of the swing
local SLOWED_SCALE, SLOWED_TIME = 0.15, 3 -- a perfectly dodged attacker: this fast, for this long
local SLOWED_REACH = 120                  -- (a blow from nobody in particular: whoever is nearest, this close)
local PERFECT_STAMINA = 25
local SPARK_TIME, GLINT_TIME = 0.3, 0.32

combat.counter = 0   -- the next cut is a counter while this runs
combat.sparks = {}
combat.glints = {}
combat.ticked = {}      -- the monsters and bosses that ran this frame (and the last): who could be slowed
combat.lastTicked = {}

function combat:clear()
    self.sparks, self.glints = {}, {}
    self.ticked, self.lastTicked = {}, {}
    self.counter = 0
end

-- one frame of `who` (a monster or a boss, its body in who.physics) in its own
-- time: returns the dt to run it with. Slowed, its body is kept at a fraction
-- of the speed its own code gives it (combat:slowOut), and here that speed is
-- handed back, so the code never knows
function combat:slowIn(who, dt)
    self.ticked[who] = true
    if who.slowScaled and who.physics then
        local vx, vy = who.physics:getLinearVelocity()
        who.physics:setLinearVelocity(vx / who.slowScaled, vy / who.slowScaled)
    end
    who.slowScaled = nil
    if (who.slowTimer or 0) <= 0 then return dt end
    who.slowTimer = who.slowTimer - dt
    return dt * SLOWED_SCALE
end

function combat:slowOut(who)
    if (who.slowTimer or 0) <= 0 or not who.physics or who.dead then return end
    local vx, vy = who.physics:getLinearVelocity()
    who.physics:setLinearVelocity(vx * SLOWED_SCALE, vy * SLOWED_SCALE)
    who.slowScaled = SLOWED_SCALE
end

function combat:slowed(who)
    return (who.slowTimer or 0) > 0
end

-- the attacker of a blow from (x, y) that came from nobody in particular (a
-- shot, a touch): whoever ran lately and stands nearest
local function nearestAttacker(x, y)
    local best, bestD = nil, SLOWED_REACH
    for _, list in ipairs({ combat.ticked, combat.lastTicked }) do
        for who in pairs(list) do
            if not who.dead and who.physics then
                local ex, ey = who.physics:getPosition()
                local d = distanceBetween(x, y, ex, ey)
                if d < bestD then best, bestD = who, d end
            end
        end
    end
    return best
end

function combat:slow(who)
    if not who or not who.physics or who.dead then return end
    who.slowTimer = SLOWED_TIME
    local ex, ey = who.physics:getPosition()
    floatTexts:spawn(ex, ey - 22, "SLOWED", {0.6, 0.8, 1}, { life = 1 })
end

function combat:update(dt)
    self.lastTicked, self.ticked = self.ticked, {}
    if self.counter > 0 then self.counter = self.counter - dt end
    for i = #self.sparks, 1, -1 do
        local s = self.sparks[i]
        s.t = s.t + dt
        if s.t >= SPARK_TIME then table.remove(self.sparks, i) end
    end
    for i = #self.glints, 1, -1 do
        local g = self.glints[i]
        g.t = g.t + dt
        if g.t >= GLINT_TIME then table.remove(self.glints, i) end
    end
end

-- a monster's blow is coming: a star flashes on it ("parry" white, "dodge" red)
function combat:glint(x, y, kind)
    table.insert(self.glints, { x = x, y = y, t = 0, kind = kind or "parry" })
end

-- is the hero's sword up to meet a blow coming from (x, y)?
function combat:parrying(x, y)
    if (player.parryTimer or 0) <= 0 then return false end
    local px, py = player:getPosition()
    local dx, dy = x - px, y - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d > PARRY_REACH then return false end
    if d < 1 then return true end
    local a = player.attackDir
    return (a.x * dx + a.y * dy) / d >= PARRY_ARC
end

-- can anything land on the hero at all right now?
local function open()
    return not (isPlayerFrozen() or player.damagedTimer > 0 or godMode)
end

-- the blow reaches the hero: slipped (a roll, a dodge, a Shadow Step) or it lands
local function land(amount, x, y, boss, attacker)
    if player:evading() then
        combat:evaded(x, y, attacker)
        return "evaded"
    end
    player:hurt(amount, x, y, boss)
    return "hit"
end

-- a blow that can be parried, from (x, y) by `attacker` (nil for a thrown one):
-- "clash", "evaded", "hit", or nil when nothing can land on the hero right now
function combat:melee(attacker, amount, x, y, boss)
    if not open() then return nil end
    if self:parrying(x, y) then
        self:clash(attacker, x, y)
        return "clash"
    end
    return land(amount, x, y, boss, attacker)
end

-- a blow that can only be dodged: "evaded", "hit" or nil
function combat:unblockable(amount, x, y, boss)
    if not open() then return nil end
    return land(amount, x, y, boss)
end

-- blade on blade: neither is hurt
function combat:clash(attacker, x, y)
    local px, py = player:getPosition()
    local mx, my = (px + x) / 2, (py + y) / 2 - 4
    local rays = {}
    for i = 1, 9 do
        local a = math.random() * math.pi * 2
        table.insert(rays, { a = a, len = 6 + math.random() * 8 })
    end
    table.insert(self.sparks, { x = mx, y = my, t = 0, rays = rays })
    dj.play(sounds.items.sword, "static", "effect", 1, 1.8)
    dj.play(sounds.items.sword, "static", "effect", 0.8, 0.6)
    shake:start(0.12, 2, 0.02)
    globalStun = math.max(globalStun, 0.09)
    -- the hero is pushed back a step, sword still up
    local away = vector(px - x, py - y)
    if away:len() < 0.01 then away = player.attackDir * -1 end
    away = away:normalized()
    player:stepBack(away, 150, 0.12)
    player.parryTimer = 0
    self.counter = self.COUNTER_TIME
    floatTexts:spawn(mx, my - 10, "CLASH!", {1, 0.92, 0.6}, { life = 0.8 })
    if attacker and attacker.onClash then attacker:onClash(away * -1) end
end

-- the hero slipped a blow from (x, y) (by `attacker`, when it's known): right as
-- it came, it's a perfect dodge (once a move)
function combat:evaded(x, y, attacker)
    if player.perfectUsed then return end
    if love.timer.getTime() - (player.evadeStart or -10) > self.PERFECT_WINDOW then return end
    player.perfectUsed = true
    self:slow(attacker or nearestAttacker(x, y))
    self.counter = self.COUNTER_TIME
    player.stamina = math.min(player.staminaMax, player.stamina + PERFECT_STAMINA)
    floatTexts:spawn(player:getX(), player:getY() - 16, "PERFECT!", {0.6, 0.95, 1}, { big = true, life = 0.9 })
    dj.play("sounds/items/manaFull.wav", "static", "effect", 0.7, 1.4)
    local px, py = player:getPosition()
    for i = 0, 5 do
        local a = i / 6 * math.pi * 2
        table.insert(player.afterimages, { x = px + math.cos(a) * 7, y = py + math.sin(a) * 4, dirX = player.dirX,
            life = 0.35, maxLife = 0.35, color = { 0.6, 0.95, 1 } })
    end
end

-- the hero's cut on `target`: the damage, and whether it's a counter (right
-- after a clash or a perfect dodge, or on anyone a perfect dodge slowed)
function combat:cutPower(base, target)
    if self.counter > 0 or (target and self:slowed(target)) then return base * self.COUNTER_BONUS, true end
    return base, false
end

-- a counter landed (the one after a clash is spent; a slowed monster takes them
-- until it wears off)
function combat:countered(x, y)
    self.counter = 0
    globalStun = math.max(globalStun, 0.07)
    shake:start(0.1, 1.5, 0.02)
    floatTexts:spawn(x, y - 14, "COUNTER! x" .. self.COUNTER_BONUS, {1, 0.75, 0.3}, { life = 0.8 })
end

----------------------------------------------------------------------- draw

-- in the world: the clash sparks, the glints (both glow), and a ring of
-- ticking marks round the feet of anyone slowed
function combat:draw()
    local slowed = {}
    for who in pairs(self.ticked) do
        if self:slowed(who) and who.physics and not who.dead then table.insert(slowed, who) end
    end
    if #self.sparks == 0 and #self.glints == 0 and #slowed == 0 then return end
    pixelfx.world(function()
        local now = love.timer.getTime()
        for _, who in ipairs(slowed) do
            local ex, ey = who.physics:getPosition()
            local fade = math.min(1, who.slowTimer / 0.5) -- (fades out as it wears off)
            love.graphics.setLineWidth(1)
            for i = 0, 7 do
                local a = i / 8 * math.pi * 2 + now * 0.8
                love.graphics.setColor(0.6, 0.8, 1, (0.45 + 0.35 * math.sin(now * 4 + i)) * fade)
                love.graphics.line(ex + math.cos(a) * 9, ey + 3 + math.sin(a) * 4, ex + math.cos(a + 0.4) * 9, ey + 3 + math.sin(a + 0.4) * 4)
            end
        end
        love.graphics.setBlendMode("add")
        for _, s in ipairs(self.sparks) do
            local p = s.t / SPARK_TIME
            love.graphics.setColor(1, 0.95, 0.7, 0.9 * (1 - p))
            love.graphics.circle("fill", s.x, s.y, 5 * (1 - p) + 1)
            love.graphics.setLineWidth(1)
            for _, r in ipairs(s.rays) do
                local r0, r1 = r.len * p * 0.6, r.len * (0.4 + p)
                love.graphics.line(s.x + math.cos(r.a) * r0, s.y + math.sin(r.a) * r0, s.x + math.cos(r.a) * r1, s.y + math.sin(r.a) * r1)
            end
            love.graphics.setColor(1, 1, 1, 0.7 * (1 - p))
            love.graphics.circle("line", s.x, s.y, 3 + 10 * p)
        end
        for _, g in ipairs(self.glints) do
            local p = g.t / GLINT_TIME
            local size = 7 * math.sin(p * math.pi)
            if g.kind == "dodge" then love.graphics.setColor(1, 0.25, 0.2, 1) else love.graphics.setColor(1, 1, 0.85, 1) end
            love.graphics.polygon("fill", g.x, g.y - size, g.x + size * 0.22, g.y, g.x, g.y + size, g.x - size * 0.22, g.y)
            love.graphics.polygon("fill", g.x - size, g.y, g.x, g.y - size * 0.22, g.x + size, g.y, g.x, g.y + size * 0.22)
            love.graphics.circle("fill", g.x, g.y, size * 0.3)
        end
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end)
end
