-- Gula, Demon of Gluttony: the dungeon boss who cursed Rick with endless hunger.
--
-- A floating demon that circles the hero and: spits fans of hunger orbs (volley
-- after volley, each fanning out between the last one's orbs), raises skeletons
-- through summoning circles, lunges with its huge mouth (again and again),
-- unleashes its Hunger Nova (it draws the hall's light into its belly, then
-- blasts it out in waves of crackling energy), and fires a beam of crackling
-- lightning across the hall that drags after the hero while it burns (a dashed
-- line shows where it starts; dodge, roll or Shadow Step through the waves and
-- the beam). At 40% health it goes
-- berserk: red, faster, untouchable and hitting much harder. lairStory takes it
-- from there (src/levels/lairStory.lua): when Rick steps in, Gula gathers the
-- same devouring spell in its jaws for him (chargeAt), and his domain freezes
-- it before it can fire.
--
-- Like Rick, Gula is not in the `enemies` list: its collider uses the 'Enemy'
-- class with `parent` set to this table, so every weapon hits it.

local FRAME_W, FRAME_H = 58, 54
local FRAME_CLOSED, FRAME_OPEN, FRAME_WIDE = 1, 2, 3
local HOVER = 24         -- how high the sprite floats above its shadow
local BERSERK_AT = 0.4   -- share of health left when it goes berserk
local CHARGE_TIME = 4.4  -- the devouring spell takes this long to gather...
local CHARGE_CAP = 0.94  -- ...and only ever gets this close to firing
local LASER_RANGE = 380  -- the beam crosses the hall until a wall stops it
local NOVA_SQUASH = 0.6  -- the nova's waves spread over the floor: drawn (and felt) as flat ellipses
local VOLLEY_GAP = 0.28  -- seconds between its volleys of orbs

-- the beam is drawn from the magic pack's laser sheet (sprites/effects/magic/laser.png):
-- frame 2 is the flash as it fires, 3-5 the beam at full power, 6-8 it thinning
-- and breaking apart. The beam runs along row BEAM_MID; the first BEAM_CAP columns
-- are its rounded end, the rest repeats out to the wall
local BEAM_MID = 35.5
local BEAM_CAP = 8
local BEAM_TILE = 72 - BEAM_CAP
local BEAM_GROW = 0.07   -- it shoots out to the wall this fast...
local BEAM_FADE = 0.24   -- ...and comes apart over this long at the end (harmless once it thins to a thread)
local SPLASH_FRAME = 0.05 -- a hunger orb bursting (splash.png, frames 2-6)
local PUFF_FRAME = 0.06   -- a burst of smoke (smokeBurst.png, 8 frames)

local TAUNTS = { "So hungry...", "You look delicious.", "Feed me!", "I'll swallow you whole!", "Kneel to your hunger!" }

local quads = nil
local beamQuad = nil

-- one stretch of the laser sheet (columns sx to sx + w of `frame`), laid along the beam at d
local function beamPiece(image, frame, sx, w, d, sy, flip)
    beamQuad:setViewport((frame - 1) * 72 + sx, 0, w, 72, image:getDimensions())
    love.graphics.draw(image, beamQuad, d, 0, 0, flip or 1, sy, 0, BEAM_MID)
end

-- the beam out to `reach`: the sheet's rounded end at the mouth, then its body
-- over and over to the wall, each stretch on its own frame so the edge never sits still
local function beamStrip(image, reach, sy, frameAt)
    beamPiece(image, frameAt(0), 0, math.min(BEAM_CAP, reach), 0, sy)
    local k = 0
    for d = BEAM_CAP, reach - 1, BEAM_TILE do
        k = k + 1
        beamPiece(image, frameAt(k), BEAM_CAP, math.min(BEAM_TILE, reach - d), d, sy)
    end
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- how far (px, py) is from the segment a-b, and the closest point on it
local function toSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = math.max(0.0001, dx * dx + dy * dy)
    local t = clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0, 1)
    local cx, cy = ax + dx * t, ay + dy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), cx, cy
end

-- a jagged line from (x1, y1) to (x2, y2), wandering up to `spread` either side
local function bolt(x1, y1, x2, y2, spread, step)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local ux, uy, nx, ny = dx / len, dy / len, -dy / len, dx / len
    local points = { x1, y1 }
    for d = step, len - step, step do
        local off = (math.random() - 0.5) * 2 * spread
        table.insert(points, x1 + ux * d + nx * off)
        table.insert(points, y1 + uy * d + ny * off)
    end
    table.insert(points, x2)
    table.insert(points, y2)
    return points
end

function spawnGula(x, y, arena)
    local g = {}
    g.x, g.y = x, y
    g.arena = arena
    g.maxHealth = 85
    g.health = g.maxHealth
    g.state = "sleep"
    g.timer = 0
    g.frame = FRAME_CLOSED
    g.float = 0
    g.flashTimer = 0
    g.stunTimer = 0
    g.dizzyTimer = 0
    g.hitCooldown = 0
    g.hookable = false
    g.invulnerable = true
    g.noContactDamage = true
    g.fighting = false
    g.berserk = false
    g.frozen = false
    g.freezeTime = 0
    g.burnTicks, g.burnTimer = 0, 0
    g.tauntTimer = 6
    g.lastAction = nil
    g.orbs, g.rings, g.circles = {}, {}, {}
    g.debris = {}         -- floor flung up by the nova
    g.splashes = {}       -- hunger orbs bursting
    g.puffs = {}          -- smoke: where the beam struck, and where its servants rise
    g.novaFlash = 0
    g.minions = {}
    g.speech = nil
    g.strikeOffset = -HOVER + 6 -- where the Storm Staff's lightning meets it (its body, not its shadow)
    g.boss = true -- its hits stagger the hero (player:hurt)

    g.physics = world:newBSGRectangleCollider(x - 14, y - 10, 28, 20, 6)
    g.physics:setCollisionClass('Enemy')
    g.physics:setFixedRotation(true)
    g.physics:setLinearDamping(6)
    g.physics:setMass(10)
    g.physics.parent = g

    if not quads then
        local sheet = sprites.enemies.gulaSheet
        quads = {}
        for i = 1, 3 do
            quads[i] = love.graphics.newQuad((i - 1) * FRAME_W, 0, FRAME_W, FRAME_H, sheet:getDimensions())
        end
        beamQuad = love.graphics.newQuad(0, 0, 72, 72, sprites.effects.magic.laser:getDimensions())
    end

    ----------------------------------------------------------------- helpers

    function g:value(normal, berserk)
        return self.berserk and berserk or normal
    end

    function g:toPlayer()
        local dx, dy = player:getX() - self.x, player:getY() - self.y
        local d = math.max(0.001, math.sqrt(dx * dx + dy * dy))
        return dx / d, dy / d, d
    end

    function g:say(text, color, big)
        floatTexts:spawn(self.x, self.y - HOVER - 30, text, color or {0.85, 0.6, 1}, { big = big, life = 1.6 })
    end

    function g:inArena(x, y, margin)
        local a = self.arena
        return clamp(x, a.x + margin, a.x + a.w - margin), clamp(y, a.y + margin, a.y + a.h - margin)
    end

    ----------------------------------------------------------------- the fight

    function g:wake()
        self.state = "awake"
        self.frame = FRAME_OPEN
    end

    function g:beginFight()
        self.fighting = true
        self.invulnerable = false
        self.noContactDamage = false
        self:idle(1)
    end

    function g:goBerserk()
        self.berserk = true
        self.invulnerable = true -- its hunger can't be stopped any more
        self:say("GRAAAH! I HUNGER!", {1, 0.3, 0.3}, true)
        shake:start(0.6, 4, 0.03)
        dj.play(sounds.items.explosion, "static", "effect", 0.8, 0.5)
        self:idle(0.6)
        if lairStory then lairStory:onBerserk() end
    end

    function g:idle(seconds)
        self.state = "idle"
        self.timer = seconds
        self.frame = FRAME_CLOSED
        -- drift to a spot around the hero
        local _, _, d = self:toPlayer()
        local a = math.random() * math.pi * 2
        local r = self:value(70, 50)
        self.driftX, self.driftY = self:inArena(player:getX() + math.cos(a) * r, player:getY() + math.sin(a) * r * 0.7, 30)
    end

    function g:chooseAction()
        local options = { "orbs", "orbs", "nova", "dash", "summon", "laser" }
        if self.berserk then options = { "orbs", "nova", "dash", "dash", "laser" } end
        local live = 0
        for _, m in ipairs(self.minions) do if not m.dead then live = live + 1 end end
        local pick
        for _ = 1, 4 do
            pick = options[math.random(#options)]
            if pick ~= self.lastAction and not (pick == "summon" and live >= 2) then break end
        end
        self.lastAction = pick
        if pick == "laser" then return self:chargeLaser() end
        if pick == "nova" then return self:chargeNova() end
        self.state = pick .. "Wind"
        self.timer = self:value(({ orbs = 0.5, nova = 0.7, dash = 0.55, summon = 0.8 })[pick], 0.3)
        self.frame = FRAME_OPEN
        if pick == "summon" then self:say("Rise, my servants!") end
        if pick == "dash" then self.dashesLeft = self:value(1, 2) end -- lunges after the first
    end

    -- the first volley of orbs; more follow (g:update, state "orbs")
    function g:fireOrbs()
        self.volley = 0
        self.volleysLeft = self:value(1, 2)
        self:orbVolley()
        self.state = "orbs"
        self.timer = VOLLEY_GAP
    end

    -- a fan of orbs at the hero: each volley a little quicker, fanning out
    -- between the last one's orbs
    function g:orbVolley()
        local dx, dy = self:toPlayer()
        local count = self:value(5, 7)
        local spread = self:value(0.7, 1.1)
        local speed = self:value(95, 135) + 12 * self.volley
        local step = spread / (count - 1)
        local offset = (self.volley % 2) * step / 2
        for i = 1, count do
            local a = math.atan2(dy, dx) + (i - (count + 1) / 2) * step + offset
            table.insert(self.orbs, { x = self.x, y = self.y - 4, vx = math.cos(a) * speed, vy = math.sin(a) * speed, life = 3 })
        end
        dj.play(sounds.enemies.projectile, "static", "effect", 0.9, 0.6 + 0.08 * self.volley)
        self.frame = FRAME_WIDE
    end

    -- the Hunger Nova: it draws the hall's light into its belly (motes rushing
    -- in, a ring closing on it, a glow swelling)... then lets it all out at once
    function g:chargeNova()
        self.state = "novaWind"
        self.timer = self:value(0.9, 0.5)
        self.novaTotal = self.timer
        self.frame = FRAME_OPEN
        self.novaMotes = {}
        -- the inhale is made to last 0.9 s: quicker when berserk
        dj.play("sounds/enemies/gulaNovaCharge.wav", "static", "effect", 0.9, 0.9 / self.timer)
    end

    function g:updateNovaCharge(dt)
        local p = 1 - math.max(0, self.timer) / self.novaTotal
        if math.random() < dt * (30 + 60 * p) then
            table.insert(self.novaMotes, { a = math.random() * math.pi * 2, r = 50 + math.random() * 40, speed = 90 + math.random() * 80 })
        end
        for i = #self.novaMotes, 1, -1 do
            local m = self.novaMotes[i]
            m.r = m.r - dt * m.speed
            m.a = m.a + dt * 1.5
            if m.r <= 4 then table.remove(self.novaMotes, i) end
        end
    end

    -- 0..1 through the wind-up
    function g:novaCharge()
        if self.state ~= "novaWind" then return 0 end
        return 1 - math.max(0, self.timer) / self.novaTotal
    end

    function g:startNova()
        local cx, cy = self.x, self.y + 4
        for i = 0, self:value(2, 3) do
            table.insert(self.rings, { x = cx, y = cy, r = 6, delay = i * 0.35, speed = self:value(130, 165), max = 170, started = i == 0 })
        end
        self.novaMotes = nil
        self.burst = { x = self.x, y = self.y - HOVER + 8, t = 0 }
        self.scorch = { x = cx, y = cy, t = 0 }
        self.novaFlash = 1
        -- chunks of the floor thrown out, and sparks
        for _ = 1, 18 do
            local a = math.random() * math.pi * 2
            local speed = 50 + math.random() * 90
            table.insert(self.debris, {
                x = cx + math.cos(a) * 6, y = cy + math.sin(a) * 4, z = 0,
                vx = math.cos(a) * speed, vy = math.sin(a) * speed * NOVA_SQUASH, vz = 60 + math.random() * 90,
                size = 1 + math.random() * 2, spin = math.random() * 6, life = 0.9 + math.random() * 0.6, spark = math.random() < 0.4,
            })
        end
        shake:start(0.45, 4, 0.03)
        dj.play("sounds/enemies/gulaNova.wav", "static", "effect", 1, self:value(1, 0.92))
        self.frame = FRAME_WIDE
        self.state = "recover"
        self.timer = self:value(0.7, 0.2)
    end

    function g:startDash()
        local dx, dy = self:toPlayer()
        local speed = self:value(230, 300)
        self.vx, self.vy = dx * speed, dy * speed
        self.state = "dash"
        self.timer = 0.55
        self.dashHit = false
        self.frame = FRAME_WIDE
        dj.play(sounds.player.roll, "static", "effect", 1, 0.5)
    end

    -------------------------------------------------------------- the beam

    function g:mouth()
        return self.x, self.y - HOVER + 8
    end

    -- where a beam from (x, y) at `angle` hits a wall
    function g:laserReach(x, y, angle)
        local dx, dy = math.cos(angle), math.sin(angle)
        for d = 12, LASER_RANGE, 6 do
            local px, py = x + dx * d, y + dy * d
            if #world:queryCircleArea(px, py, 2, {'Wall'}) > 0 then return px, py end
        end
        return x + dx * LASER_RANGE, y + dy * LASER_RANGE
    end

    function g:aimLaser()
        local mx, my = self:mouth()
        self.laserAngle = math.atan2(player:getY() - my, player:getX() - mx)
        self.laserEndX, self.laserEndY = self:laserReach(mx, my, self.laserAngle)
    end

    -- lightning gathers in its jaws while a dashed line follows the hero; for
    -- the last moments the aim locks (the line blinks red): time to move
    function g:chargeLaser()
        self.state = "laserWind"
        self.timer = self:value(1.0, 0.65)
        self.laserLock = self.timer * 0.35
        self.frame = FRAME_OPEN
        self:aimLaser()
        dj.play(sounds.enemies.gulaCharge, "static", "effect", 0.9, self:value(1, 1.3))
    end

    function g:fireLaser()
        local mx, my = self:mouth()
        self.state = "laser"
        self.frame = FRAME_WIDE
        self.beam = {
            x1 = mx, y1 = my, x2 = self.laserEndX, y2 = self.laserEndY,
            t = 0, life = self:value(0.7, 0.55), width = self:value(11, 15), hit = false, flash = 1, tick = 0,
            angle = self.laserAngle,
        }
        self:crackle()
        shake:start(self.beam.life, self:value(2, 3), 0.02)
        dj.play(sounds.enemies.gulaThunder, "static", "effect", 1, self:value(1, 0.9))
        dj.play("sounds/items/laser.wav", "static", "effect", 0.6, 0.4)
    end

    -- fresh lightning along the beam: redrawn many times a second, so it flickers
    function g:crackle()
        local b = self.beam
        b.flicker = 0.045
        b.tick = b.tick + 1 -- the beam's ragged edge shifts too
        -- now and then the lightning flares and lights the hall again
        if b.t > 0.1 and math.random() < 0.22 then b.flash = math.max(b.flash, 0.45) end
        b.bolts = {
            bolt(b.x1, b.y1, b.x2, b.y2, b.width * 0.3, 8),
            bolt(b.x1, b.y1, b.x2, b.y2, b.width * 0.85, 10),
            bolt(b.x1, b.y1, b.x2, b.y2, b.width * 0.85, 12),
        }
        -- forks leaping off the beam
        local dx, dy = b.x2 - b.x1, b.y2 - b.y1
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local nx, ny = -dy / len, dx / len
        b.forks = {}
        for _ = 1, 5 do
            local f = math.random()
            local side = math.random() < 0.5 and -1 or 1
            local x, y = b.x1 + dx * f, b.y1 + dy * f
            local reach = b.width * (1 + math.random() * 1.6)
            table.insert(b.forks, bolt(x, y, x + nx * side * reach + dx / len * (math.random() - 0.5) * 14,
                y + ny * side * reach + dy / len * (math.random() - 0.5) * 14, 3, 4))
        end
    end

    function g:updateBeam(dt)
        local b = self.beam
        b.t = b.t + dt
        b.flash = math.max(0, b.flash - dt * 7)
        b.flicker = b.flicker - dt
        if b.flicker <= 0 then self:crackle() end
        -- while it burns it drags across the hall after the hero, slower than
        -- they can run (but dodging through it is safer)
        if self:beamGrowth() >= 1 and b.life - b.t > BEAM_FADE then
            local want = math.atan2(player:getY() - b.y1, player:getX() - b.x1)
            local diff = (want - b.angle + math.pi) % (math.pi * 2) - math.pi
            local turn = self:value(0.6, 1) * dt
            b.angle = b.angle + math.max(-turn, math.min(turn, diff))
            b.x2, b.y2 = self:laserReach(b.x1, b.y1, b.angle)
        end
        -- standing in it burns (rolling or Shadow Step slips through), until it
        -- thins to a thread
        if not b.hit and b.t > 0.04 and b.life - b.t > BEAM_FADE * 2 / 3 and player.state ~= 0.5
            and player.shadowInvuln <= 0 and not isPlayerFrozen() and player.damagedTimer <= 0 then
            local grow = self:beamGrowth()
            local d, cx, cy = toSegment(player:getX(), player:getY(), b.x1, b.y1,
                b.x1 + (b.x2 - b.x1) * grow, b.y1 + (b.y2 - b.y1) * grow)
            if d < b.width * 0.5 + 4 then
                b.hit = true
                player:hurt(self:value(1, 1.5), cx, cy, true)
            end
        end
        if b.t >= b.life then
            -- a last wisp of smoke where it struck
            table.insert(self.puffs, { x = b.x2, y = b.y2 + 6, t = 0, scale = 0.35 })
            self.beam = nil
            self.state = "recover"
            self.timer = self:value(0.6, 0.2)
        end
    end

    -- 0..1: how strongly the beam burns right now (it snaps on and tapers off)
    function g:beamPower()
        local b = self.beam
        if not b then return 0 end
        return math.min(1, b.t / 0.06) * math.min(1, (b.life - b.t) / 0.18)
    end

    -- 0..1: how far out from its mouth the beam has shot
    function g:beamGrowth()
        return math.min(1, self.beam.t / BEAM_GROW)
    end

    -- the laser sheet's frame for stretch k of the beam right now: full power
    -- (each stretch a different one of the three, shifting as it crackles), then
    -- thinning, then breaking apart
    function g:beamFrame(k)
        local b = self.beam
        local left = b.life - b.t
        if left < BEAM_FADE then return math.min(8, 6 + math.floor((1 - left / BEAM_FADE) * 3)) end
        return 3 + (k + b.tick) % 3
    end

    function g:summon()
        for i = -1, 1, 2 do
            local x, y = self:inArena(self.x + i * 40, self.y + 26, 24)
            table.insert(self.circles, { x = x, y = y, t = 0 })
        end
        dj.play("sounds/items/manaFull.wav", "static", "effect", 0.5, 0.5)
        self.state = "recover"
        self.timer = 0.8
    end

    ----------------------------------------------------------------- damage

    function g:hit(damage, dir, stun, dizziness)
        if self.invulnerable or self.frozen or not self.fighting then
            if self.fighting and damage > 0 then self.flashTimer = 0.05 end
            return
        end
        if damage <= 0 then return end
        if self.hitCooldown > 0 and damage < 3 then return end
        self.hitCooldown = 0.2
        globalStun = 0.035
        shake:start(0.08, 1, 0.02)
        dj.play(sounds.enemies.hurt, "static", "effect", 1, 0.6 + math.random() * 0.2)
        self:takeDamage(damage, dir or vector(0, 1))
    end

    function g:takeDamage(amount, dir)
        self.health = math.max(0, self.health - amount)
        self.flashTimer = 0.15
        for _ = 1, 10 do
            effects:spawn("damage", self.x, self.y - HOVER, { dir = dir })
        end
        if not self.berserk and self.health <= self.maxHealth * BERSERK_AT then
            self.health = math.ceil(self.maxHealth * BERSERK_AT)
            self:goBerserk()
        end
    end

    function g:burn()
        if self.invulnerable or self.frozen then return end
        self.burnTicks = 3
        self.burnTimer = 0.5
    end

    -- Rick's domain: frozen solid
    function g:freeze()
        self.beam = nil
        if self.charge then
            -- the spell dies in its jaws
            dj.play("sounds/items/fizzle.wav", "static", "effect", 1, 0.6)
            self.charge, self.chargeMotes = nil, nil
        end
        self.frozen = true
        self.fighting = false
        self.invulnerable = true
        self.noContactDamage = true
        self.state = "frozen"
        self.orbs, self.rings, self.circles, self.debris = {}, {}, {}, {}
        self.splashes, self.puffs = {}, {}
        self.novaMotes, self.burst, self.novaFlash = nil, nil, 0
        self.physics:setLinearVelocity(0, 0)
        for _, m in ipairs(self.minions) do m.health = 0 end
    end

    -- its servants still standing
    function g:liveMinions()
        local live = {}
        for _, m in ipairs(self.minions) do
            if not m.dead and m.physics then table.insert(live, m) end
        end
        return live
    end

    -- the hero is down: its servants stand over them, waiting
    function g:holdMinions()
        for _, m in ipairs(self:liveMinions()) do
            m.stunTimer = math.huge
            m.physics:setLinearVelocity(0, 0)
        end
    end

    -- the same devouring spell that felled the hero, gathering in its jaws for a
    -- new victim; it trembles on the edge of firing until something stops it
    function g:chargeAt(target)
        self.state = "devourWind"
        self.frame = FRAME_WIDE
        self.charge = 0
        self.chargeTarget = target
        self.chargeMotes = {}
        self.orbs, self.rings = {}, {}
        -- it rises off the hero to face the newcomer: up, and to the far side
        local side = target.x >= player:getX() and -1 or 1
        self.chargeX, self.chargeY = self:inArena(player:getX() + side * 40, player:getY() - 44, 30)
        dj.play("sounds/items/manaHum.wav", "static", "effect", 1, 0.45)
    end

    -- the final lunge at a fallen hero (the fight is over: no more taunts)
    function g:loom()
        self.fighting = false
        self.beam = nil
        self.state = "loom"
        self.frame = FRAME_WIDE
        self.orbs, self.rings, self.circles = {}, {}, {}
        self.novaMotes = nil
    end

    ----------------------------------------------------------------- update

    function g:updateShots(dt)
        local hurtBy = self:value(0.5, 1.5)
        for i = #self.orbs, 1, -1 do
            local o = self.orbs[i]
            o.x, o.y = o.x + o.vx * dt, o.y + o.vy * dt
            o.life = o.life - dt
            local gone = o.life <= 0 or #world:queryCircleArea(o.x, o.y, 2, {'Wall'}) > 0
            if not gone and not isPlayerFrozen() and player.damagedTimer <= 0 and not player:untouchable()
                and distanceBetween(o.x, o.y, player:getX(), player:getY()) < 7 then
                player:hurt(hurtBy, o.x - o.vx, o.y - o.vy, true)
                gone = true
            end
            if gone then
                -- it bursts, splashing back the way it came
                table.insert(self.splashes, { x = o.x, y = o.y, t = 0, flip = o.vx > 0 and 1 or -1 })
                table.remove(self.orbs, i)
            end
        end
        for i = #self.splashes, 1, -1 do
            local s = self.splashes[i]
            s.t = s.t + dt
            if s.t >= SPLASH_FRAME * 5 then table.remove(self.splashes, i) end
        end
        for i = #self.puffs, 1, -1 do
            local p = self.puffs[i]
            p.t = p.t + dt
            if p.t >= PUFF_FRAME * 8 then table.remove(self.puffs, i) end
        end
        for i = #self.rings, 1, -1 do
            local r = self.rings[i]
            if r.delay > 0 then
                r.delay = r.delay - dt
            else
                if not r.started then
                    -- each wave after the first goes off with its own pulse
                    r.started = true
                    self.novaFlash = math.max(self.novaFlash, 0.5)
                    shake:start(0.2, 2.5, 0.03)
                    dj.play("sounds/enemies/gulaNova.wav", "static", "effect", 0.55, 1.25)
                end
                r.r = r.r + r.speed * dt
                if not r.hit and player.state ~= 0.5 and player.shadowInvuln <= 0 and not isPlayerFrozen() and player.damagedTimer <= 0 then
                    -- the wave is a flat ellipse on the floor: it hits where it is drawn
                    local dx, dy = player:getX() - r.x, (player:getY() - r.y) / NOVA_SQUASH
                    if math.abs(math.sqrt(dx * dx + dy * dy) - r.r) < 5 then
                        r.hit = true
                        player:hurt(hurtBy, r.x, r.y, true)
                    end
                end
                if r.r > r.max then table.remove(self.rings, i) end
            end
        end
        -- the blast's leftovers: floor chunks falling back, the flash, the scorch
        for i = #self.debris, 1, -1 do
            local d = self.debris[i]
            d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
            d.vz = d.vz - 320 * dt
            if d.z < 0 then
                d.z, d.vz = 0, -d.vz * 0.35
                d.vx, d.vy = d.vx * 0.5, d.vy * 0.5
            end
            d.life = d.life - dt
            if d.life <= 0 then table.remove(self.debris, i) end
        end
        self.novaFlash = math.max(0, self.novaFlash - dt * 3)
        if self.burst then
            self.burst.t = self.burst.t + dt
            if self.burst.t > 0.6 then self.burst = nil end
        end
        if self.scorch then
            self.scorch.t = self.scorch.t + dt
            if self.scorch.t > 3 then self.scorch = nil end
        end
        for i = #self.circles, 1, -1 do
            local c = self.circles[i]
            c.t = c.t + dt
            if c.t >= 1 then
                table.remove(self.circles, i)
                local e = spawnEnemy(c.x - 6, c.y - 8, "skeleton", { form = 1 })
                if e then
                    -- out of the circle, a moment to snarl, then straight at the hero
                    e.state = 99
                    e.animTimer = 0.4
                    table.insert(self.minions, e)
                end
                table.insert(self.puffs, { x = c.x, y = c.y + 2, t = 0, scale = 0.45 })
            end
        end
        for i = #self.minions, 1, -1 do
            if self.minions[i].dead then table.remove(self.minions, i) end
        end
    end

    function g:update(dt)
        self.x, self.y = self.physics:getPosition()
        self.float = self.float + dt
        if self.flashTimer > 0 then self.flashTimer = self.flashTimer - dt end
        if self.hitCooldown > 0 then self.hitCooldown = self.hitCooldown - dt end
        if self.frozen then
            self.freezeTime = self.freezeTime + dt
            self.physics:setLinearVelocity(0, 0)
            return
        end
        self:updateShots(dt)

        if self.burnTicks > 0 then
            self.burnTimer = self.burnTimer - dt
            if math.random() < dt * 20 then effects:spawn("enemyEmber", self.x, self.y - HOVER, { scale = 0.7 }) end
            if self.burnTimer <= 0 then
                self.burnTicks = self.burnTicks - 1
                self.burnTimer = 0.5
                if not self.invulnerable then self:takeDamage(0.5, vector(0, -1)) end
            end
        end

        local s = self.state
        if s == "sleep" or s == "awake" then
            self.physics:setLinearVelocity(0, 0)
        elseif s == "idle" then
            self.timer = self.timer - dt
            local dx, dy = self.driftX - self.x, self.driftY - self.y
            local d = math.sqrt(dx * dx + dy * dy)
            local speed = self:value(55, 90)
            if d > 3 then self.physics:setLinearVelocity(dx / d * speed, dy / d * speed) else self.physics:setLinearVelocity(0, 0) end
            if self.timer <= 0 then self:chooseAction() end
        elseif s == "recover" then
            self.physics:setLinearVelocity(0, 0)
            self.timer = self.timer - dt
            if self.timer <= 0 then self:idle(self:value(0.55 + math.random() * 0.45, 0.2)) end
        elseif s == "orbs" then
            -- volley after volley, re-aimed at the hero each time
            self.physics:setLinearVelocity(0, 0)
            self.timer = self.timer - dt
            if self.timer <= 0 then
                if self.volleysLeft > 0 then
                    self.volleysLeft = self.volleysLeft - 1
                    self.volley = self.volley + 1
                    self:orbVolley()
                    self.timer = VOLLEY_GAP
                else
                    self.state = "recover"
                    self.timer = self:value(0.5, 0.15)
                end
            end
        elseif s == "orbsWind" or s == "novaWind" or s == "dashWind" or s == "summonWind" then
            self.physics:setLinearVelocity(0, 0)
            self.timer = self.timer - dt
            if s == "novaWind" then self:updateNovaCharge(dt) end
            if self.timer <= 0 then
                if s == "orbsWind" then self:fireOrbs()
                elseif s == "novaWind" then self:startNova()
                elseif s == "dashWind" then self:startDash()
                else self:summon() end
            end
        elseif s == "dash" then
            self.timer = self.timer - dt
            self.physics:setLinearVelocity(self.vx, self.vy)
            if not self.dashHit and not isPlayerFrozen() and distanceBetween(self.x, self.y, player:getX(), player:getY()) < 18 then
                self.dashHit = true
                player:hurt(self:value(1, 1.5), self.x, self.y, true)
            end
            if self.timer <= 0 or self.physics:enter('Wall') then
                self.physics:setLinearVelocity(0, 0)
                if (self.dashesLeft or 0) > 0 then
                    -- turns on the hero and lunges again
                    self.dashesLeft = self.dashesLeft - 1
                    self.state = "dashWind"
                    self.timer = self:value(0.32, 0.2)
                    self.frame = FRAME_OPEN
                else
                    self.state = "recover"
                    self.timer = self:value(0.5, 0.15)
                end
            end
        elseif s == "laserWind" then
            self.physics:setLinearVelocity(0, 0)
            self.timer = self.timer - dt
            if self.timer > self.laserLock then self:aimLaser() end
            if self.timer <= 0 then self:fireLaser() end
        elseif s == "laser" then
            self.physics:setLinearVelocity(0, 0)
            self:updateBeam(dt)
        elseif s == "devourWind" then
            local dx, dy = self.chargeX - self.x, self.chargeY - self.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 2 then self.physics:setLinearVelocity(dx / d * 40, dy / d * 40) else self.physics:setLinearVelocity(0, 0) end
            self.charge = math.min(CHARGE_CAP, self.charge + dt / CHARGE_TIME)
            -- motes of stolen life spiral into its mouth
            if math.random() < dt * (20 + 40 * self.charge) then
                table.insert(self.chargeMotes, { a = math.random() * math.pi * 2, r = 28 + math.random() * 16 })
            end
            for i = #self.chargeMotes, 1, -1 do
                local m = self.chargeMotes[i]
                m.r = m.r - dt * 45
                m.a = m.a + dt * 3
                if m.r <= 3 then table.remove(self.chargeMotes, i) end
            end
        elseif s == "loom" then
            -- creeps toward the fallen hero, jaws wide
            local dx, dy, d = self:toPlayer()
            if d > 26 then self.physics:setLinearVelocity(dx * 25, dy * 25) else self.physics:setLinearVelocity(0, 0) end
        end

        if self.fighting then
            self.tauntTimer = self.tauntTimer - dt
            if self.tauntTimer <= 0 then
                self.tauntTimer = self:value(7, 3) + math.random() * 3
                self:say(TAUNTS[math.random(#TAUNTS)])
            end
        end
    end

    ----------------------------------------------------------------- draw

    function g:drawGround()
        pixelfx.world(function()
            -- shadow, the nova's scorch mark and summoning circles on the floor (the
            -- nova's waves glow: drawEmissive)
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.ellipse("fill", self.x, self.y + 6, 16, 5)
            if self.scorch then
                local fade = 1 - self.scorch.t / 3
                love.graphics.setColor(0.12, 0.02, 0.16, 0.5 * fade)
                love.graphics.ellipse("fill", self.scorch.x, self.scorch.y, 28, 28 * NOVA_SQUASH)
                love.graphics.setColor(0.04, 0, 0.07, 0.5 * fade)
                love.graphics.ellipse("fill", self.scorch.x, self.scorch.y, 15, 15 * NOVA_SQUASH)
            end
            -- each circle opens out of nothing, its runes pulsing (summonCircle.png),
            -- and flares just as the skeleton climbs out
            local sheet, frames = sprites.effects.magic.summonCircle, sprites.effects.magicQuads.summonCircle
            for _, c in ipairs(self.circles) do
                local open = math.min(1, c.t / 0.25)
                local s = 0.45 * (0.5 + 0.5 * open)
                local frame = math.min(8, 1 + math.floor(c.t * 8))
                love.graphics.setBlendMode("add")
                love.graphics.setColor(0.8, 0.3, 1, 0.15 + 0.3 * c.t)
                love.graphics.ellipse("fill", c.x, c.y, 30 * s, 15 * s)
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, open)
                love.graphics.draw(sheet, frames[frame], c.x, c.y, 0, s, s * 0.5, 36, 36)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 1, 1, 0.6 * c.t)
                love.graphics.draw(sheet, frames[frame], c.x, c.y, 0, s, s * 0.5, 36, 36)
                love.graphics.setBlendMode("alpha")
            end
            setWhite()
        end)
    end

    function g:draw()
        local bob = self.frozen and 0 or math.sin(self.float * 2.4) * 2
        local x, y = math.floor(self.x), math.floor(self.y - HOVER + bob)
        local shakeX = 0
        if self.state:sub(-4) == "Wind" or self.berserk then shakeX = (math.random() - 0.5) * (self.berserk and 2.5 or 1.5) end

        -- berserk aura
        if self.berserk and not self.frozen then
            local pulse = 0.5 + 0.5 * math.sin(self.float * 10)
            pixelfx.world(function()
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 0.15, 0.15, 0.25 + 0.2 * pulse)
                love.graphics.circle("fill", x, y, 30 + pulse * 4)
            end)
        end

        if self.frozen then
            love.graphics.setColor(0.6, 0.85, 1, 1)
        elseif self.flashTimer > 0 then
            love.graphics.setColor(1, 1, 1, 0.6)
        elseif self.berserk then
            love.graphics.setColor(1, 0.55, 0.55, 1)
        else
            setWhite()
        end
        love.graphics.draw(sprites.enemies.gulaSheet, quads[self.frame], x + shakeX, y, 0, 1, 1, FRAME_W / 2, FRAME_H / 2)
        -- set alight by a Fireball
        if self.burnTicks > 0 and not self.frozen then effects:drawFlame(x + shakeX, y + 16, 1, 0.9) end

        if self.charge or self.frozen then
            pixelfx.world(function()
            -- the devouring spell, swelling in its jaws
            if self.charge then
                local p = self.charge
                local pulse = 0.5 + 0.5 * math.sin(self.float * (8 + 24 * p))
                local tremble = p >= CHARGE_CAP and 1.5 or p
                local mx, my = x + shakeX + (math.random() - 0.5) * tremble, y + 8 + (math.random() - 0.5) * tremble
                love.graphics.setBlendMode("add")
                for _, m in ipairs(self.chargeMotes) do
                    love.graphics.setColor(1, 0.35, 0.55, 0.85)
                    love.graphics.rectangle("fill", mx + math.cos(m.a) * m.r - 0.75, my + math.sin(m.a) * m.r * 0.75 - 0.75, 1.5, 1.5)
                end
                love.graphics.setColor(1, 0.12, 0.3, 0.22 + 0.18 * pulse)
                love.graphics.circle("fill", mx, my, 5 + 15 * p + pulse * 2)
                love.graphics.setColor(1, 0.4, 0.6, 0.65)
                love.graphics.circle("fill", mx, my, 2.5 + 7 * p)
                love.graphics.setColor(1, 0.92, 0.96, 0.9)
                love.graphics.circle("fill", mx, my, 1 + 3 * p)
                love.graphics.setBlendMode("alpha")
            end

            -- encased in ice
            if self.frozen then
                local grow = math.min(1, self.freezeTime / 0.6)
                love.graphics.setColor(0.75, 0.92, 1, 0.45 * grow)
                love.graphics.polygon("fill", x - 30, y + 26, x - 34, y - 6, x - 18, y - 32, x + 6, y - 38, x + 28, y - 24, x + 34, y + 4, x + 26, y + 28)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(0.95, 1, 1, 0.85 * grow)
                love.graphics.polygon("line", x - 30, y + 26, x - 34, y - 6, x - 18, y - 32, x + 6, y - 38, x + 28, y - 24, x + 34, y + 4, x + 26, y + 28)
                love.graphics.line(x - 18, y - 32, x - 8, y + 10)
                love.graphics.line(x + 6, y - 38, x + 12, y - 4)
                love.graphics.line(x + 28, y - 24, x + 16, y + 18)
            end
            end)
        end
        setWhite()
    end

    function g:drawAir()
        pixelfx.world(function()
            -- chunks of floor thrown up by the nova (and their shadows), and sparks
            for _, d in ipairs(self.debris) do
                local a = math.min(1, d.life * 3)
                love.graphics.setColor(0, 0, 0, 0.3 * a)
                love.graphics.ellipse("fill", d.x, d.y, d.size, d.size * 0.5)
                if d.spark then
                    love.graphics.setBlendMode("add")
                    love.graphics.setColor(1, 0.75, 1, a)
                    love.graphics.rectangle("fill", d.x - 0.75, d.y - d.z - 0.75, 1.5, 1.5)
                    love.graphics.setBlendMode("alpha")
                else
                    love.graphics.setColor(0.34, 0.27, 0.32, a)
                    love.graphics.rectangle("fill", d.x - d.size / 2, d.y - d.z - d.size / 2, d.size, d.size)
                end
            end
            love.graphics.setBlendMode("add")
            for _, o in ipairs(self.orbs) do
                love.graphics.setColor(self.berserk and 1 or 0.7, 0.2, self.berserk and 0.25 or 0.9, 0.35)
                love.graphics.circle("fill", o.x, o.y, 6)
                love.graphics.setColor(1, 0.8, 1, 0.9)
                love.graphics.circle("fill", o.x, o.y, 2.5)
            end
            love.graphics.setBlendMode("alpha")
            -- orbs bursting (splash.png: blood red when it's berserk)
            local sheet, frames = sprites.effects.magic.splash, sprites.effects.magicQuads.splash
            for _, s in ipairs(self.splashes) do
                if self.berserk then love.graphics.setColor(1, 0.45, 0.5, 1) else setWhite() end
                love.graphics.draw(sheet, frames[math.min(6, 2 + math.floor(s.t / SPLASH_FRAME))], s.x, s.y + 3, 0, 0.5 * s.flip, 0.5, 27, 70)
            end
            setWhite()
        end)
    end

    -- what glows on its own (drawn over the lair's darkness, camera attached)
    function g:drawEmissive()
        pixelfx.world(function()
            if self.state == "laserWind" then self:drawLaserCharge() end
            if self.state == "novaWind" then self:drawNovaCharge() end
            self:drawNova()
            if self.beam then self:drawBeam() end
            self:drawPuffs()
        end)
        setWhite()
    end

    -- glowing smoke (smokeBurst.png) rising and drifting apart
    function g:drawPuffs()
        local sheet, frames = sprites.effects.magic.smokeBurst, sprites.effects.magicQuads.smokeBurst
        local r, gr, bl = self:beamColor()
        love.graphics.setBlendMode("add")
        for _, p in ipairs(self.puffs) do
            love.graphics.setColor(r, gr, bl, 0.7)
            love.graphics.draw(sheet, frames[math.min(8, 1 + math.floor(p.t / PUFF_FRAME))], p.x, p.y, 0, p.scale, p.scale, 36, 70)
        end
        love.graphics.setBlendMode("alpha")
    end

    -- the lightning flash and the nova's blast of light, over the whole screen
    function g:drawFlash()
        local flash = math.max(self.beam and 0.32 * self.beam.flash or 0, 0.4 * self.novaFlash)
        if flash <= 0.003 then return end
        local r, gr, bl = self:beamColor()
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.55 + 0.45 * r, 0.55 + 0.45 * gr, 0.55 + 0.45 * bl, flash)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setBlendMode("alpha")
        setWhite()
    end

    -- the light its spells throw around the hall (lighting:sources)
    function g:addLights(list)
        local r, gr, bl = self:beamColor()
        if self.state == "novaWind" then
            local p = self:novaCharge()
            table.insert(list, { x = self.x, y = self.y - HOVER + 8, radius = 30 + 50 * p, color = { r, gr, bl }, strength = 0.6 + 0.4 * p })
        end
        if self.burst then
            -- the blast lights the whole hall for a moment
            local p = self.burst.t / 0.6
            table.insert(list, { x = self.burst.x, y = self.burst.y, radius = 140 + 220 * p, strength = 1 - p })
        end
        for _, c in ipairs(self.circles) do
            table.insert(list, { x = c.x, y = c.y, radius = 20 + 22 * c.t, color = { 0.75, 0.3, 1 }, strength = 0.4 + 0.6 * c.t })
        end
        for _, ring in ipairs(self.rings) do
            if ring.delay <= 0 then
                local fade = 1 - ring.r / ring.max
                for k = 0, 3 do
                    local a = (k + 0.5) / 4 * math.pi * 2
                    table.insert(list, { x = ring.x + math.cos(a) * ring.r, y = ring.y + math.sin(a) * ring.r * NOVA_SQUASH,
                        radius = 30 + ring.r * 0.25, color = { r, gr, bl }, strength = fade })
                end
            end
        end
    end

    -- the wind-up: the hall's light rushing into its belly, a ring on the floor
    -- closing in on it, the glow in its belly swelling and crackling
    function g:drawNovaCharge()
        local p = self:novaCharge()
        local r, gr, bl = self:beamColor()
        local bx, by = self.x, self.y - HOVER + 8
        love.graphics.setBlendMode("add")
        local ring = 8 + 64 * (1 - p) ^ 1.5
        love.graphics.setColor(r, gr, bl, 0.1 + 0.12 * p)
        love.graphics.ellipse("fill", self.x, self.y + 4, ring, ring * NOVA_SQUASH)
        love.graphics.setLineWidth(1.5)
        love.graphics.setColor(r, gr, bl, 0.3 + 0.6 * p)
        love.graphics.ellipse("line", self.x, self.y + 4, ring, ring * NOVA_SQUASH)
        love.graphics.setLineWidth(1)
        for _, m in ipairs(self.novaMotes or {}) do
            local c, s = math.cos(m.a), math.sin(m.a)
            love.graphics.setColor(1, 0.85, 1, 0.85)
            love.graphics.line(bx + c * (m.r + 7), by + s * (m.r + 7) * 0.8, bx + c * m.r, by + s * m.r * 0.8)
        end
        local pulse = 0.5 + 0.5 * math.sin(self.float * 30)
        love.graphics.setColor(r, gr, bl, 0.3 + 0.3 * p)
        love.graphics.circle("fill", bx, by, 4 + 14 * p + pulse * 2)
        love.graphics.setColor(1, 0.92, 1, 0.5 + 0.45 * p)
        love.graphics.circle("fill", bx, by, 1.5 + 5 * p)
        if p > 0.4 then
            love.graphics.setLineJoin("bevel")
            for _ = 1, math.floor(p * 4) do
                local a = math.random() * math.pi * 2
                local reach = 6 + math.random() * 10 * p
                love.graphics.setColor(0.95, 0.85, 1, 0.9)
                love.graphics.line(bolt(bx, by, bx + math.cos(a) * reach, by + math.sin(a) * reach, 2, 3))
            end
        end
        love.graphics.setBlendMode("alpha")
    end

    -- the blast: a burst of light out of its heart, then waves of crackling
    -- energy rolling over the floor (their bright leading edge is what hurts)
    function g:drawNova()
        if #self.rings == 0 and not self.burst then return end
        local r, gr, bl = self:beamColor()
        love.graphics.setBlendMode("add")
        love.graphics.setLineJoin("bevel")
        for _, ring in ipairs(self.rings) do
            if ring.delay <= 0 then
                local fade = 1 - ring.r / ring.max
                local x, y, rad = ring.x, ring.y, ring.r
                -- a soft wake behind the edge
                love.graphics.setLineWidth(3.5)
                for k = 1, 5 do
                    local rr = rad - k * 3.5
                    if rr > 1 then
                        love.graphics.setColor(r, gr, bl, 0.16 * fade * (1 - k / 6))
                        love.graphics.ellipse("line", x, y, rr, rr * NOVA_SQUASH)
                    end
                end
                -- a glow around the edge, the edge, and its white-hot core
                love.graphics.setLineWidth(7)
                love.graphics.setColor(r, gr, bl, 0.22 * fade)
                love.graphics.ellipse("line", x, y, rad, rad * NOVA_SQUASH)
                love.graphics.setLineWidth(2)
                love.graphics.setColor(0.8 + 0.2 * r, 0.75 + 0.25 * gr, 0.85 + 0.15 * bl, 0.9 * fade)
                love.graphics.ellipse("line", x, y, rad, rad * NOVA_SQUASH)
                love.graphics.setLineWidth(0.8)
                love.graphics.setColor(1, 1, 1, fade)
                love.graphics.ellipse("line", x, y, rad, rad * NOVA_SQUASH)
                -- sparks riding the edge, and lightning leaping off it
                for k = 1, 20 do
                    local a = k / 20 * math.pi * 2 + rad * 0.013 + (math.random() - 0.5) * 0.1
                    love.graphics.setColor(1, 0.9, 1, fade * (0.4 + 0.6 * math.random()))
                    love.graphics.rectangle("fill", x + math.cos(a) * rad - 0.75, y + math.sin(a) * rad * NOVA_SQUASH - 0.75, 1.5, 1.5)
                end
                love.graphics.setLineWidth(1)
                for _ = 1, 3 do
                    local a = math.random() * math.pi * 2
                    local sx, sy = x + math.cos(a) * rad, y + math.sin(a) * rad * NOVA_SQUASH
                    local out = 6 + math.random() * 8
                    love.graphics.setColor(0.92, 0.85, 1, 0.9 * fade)
                    love.graphics.line(bolt(sx, sy, sx + math.cos(a) * out, sy + math.sin(a) * out * NOVA_SQUASH - math.random() * 6, 2, 3))
                end
            end
        end
        -- the burst at its heart: a swelling sphere of light and rays flying out
        local b = self.burst
        if b then
            local p = b.t / 0.6
            local ease = 1 - (1 - p) ^ 3
            love.graphics.setColor(r, gr, bl, 0.5 * (1 - p) ^ 2)
            love.graphics.circle("fill", b.x, b.y, 10 + 50 * ease)
            love.graphics.setColor(1, 0.95, 1, 0.9 * (1 - p) ^ 3)
            love.graphics.circle("fill", b.x, b.y, 5 + 22 * ease)
            love.graphics.setLineWidth(1.5)
            for k = 1, 12 do
                local a = k / 12 * math.pi * 2 + p * 0.6
                local inner, outer = 8 + 20 * ease, 20 + 90 * ease
                love.graphics.setColor(1, 0.9, 1, 0.6 * (1 - p))
                love.graphics.line(b.x + math.cos(a) * inner, b.y + math.sin(a) * inner, b.x + math.cos(a) * outer, b.y + math.sin(a) * outer)
            end
        end
        love.graphics.setLineWidth(1)
        love.graphics.setBlendMode("alpha")
    end

    -- the tint of its lightning: violet, or blood red when berserk
    function g:beamColor()
        if self.berserk then return 1, 0.35, 0.4 end
        return 0.7, 0.55, 1
    end

    function g:drawLaserCharge()
        local mx, my = self:mouth()
        local r, gr, b = self:beamColor()
        local total = self:value(1.0, 0.65)
        local p = 1 - math.max(0, self.timer) / total
        local locked = self.timer <= self.laserLock
        -- the dashed line: where the beam will go
        local dx, dy = self.laserEndX - mx, self.laserEndY - my
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len, dy / len
        local on = not locked or math.floor(self.timer * 24) % 2 == 0
        if on then
            love.graphics.setLineWidth(1)
            if locked then love.graphics.setColor(1, 0.3, 0.3, 0.9) else love.graphics.setColor(0.9, 0.85, 1, 0.55) end
            for d = 10, len - 4, 10 do
                love.graphics.line(mx + ux * d, my + uy * d, mx + ux * math.min(len, d + 6), my + uy * math.min(len, d + 6))
            end
        end
        -- lightning gathering in its jaws
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, gr, b, 0.35 + 0.3 * p)
        love.graphics.circle("fill", mx, my, 4 + 6 * p + math.random() * 1.5)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle("fill", mx, my, 1.5 + 2.5 * p)
        love.graphics.setLineWidth(1)
        for _ = 1, 2 + math.floor(p * 4) do
            local a = math.random() * math.pi * 2
            local reach = 8 + math.random() * (10 + 12 * p)
            love.graphics.setColor(0.85, 0.9, 1, 0.9)
            love.graphics.line(bolt(mx + math.cos(a) * reach, my + math.sin(a) * reach * 0.8, mx, my, 2.5, 4))
        end
        love.graphics.setBlendMode("alpha")
    end

    function g:drawBeam()
        local b = self.beam
        local power = self:beamPower()
        local r, gr, bl = self:beamColor()
        local dx, dy = b.x2 - b.x1, b.y2 - b.y1
        local len = math.sqrt(dx * dx + dy * dy)
        local grown = self:beamGrowth()
        local reach = math.max(1, math.floor(len * grown))
        local whole = b.life - b.t > BEAM_FADE -- not coming apart yet
        local sy = b.width / 11 -- the sheet's beam is 19 px across: about the width that burns
        local magic = sprites.effects.magic
        local frameAt = function(k) return self:beamFrame(k) end
        local lr, lg, lb = 0.55 + 0.45 * r, 0.55 + 0.45 * gr, 0.55 + 0.45 * bl

        -- the beam (laser.png): a glow, then the beam in its colour with the
        -- sheet's flecked edge darker, then its white-hot heart
        love.graphics.push()
        love.graphics.translate(b.x1, b.y1)
        love.graphics.rotate(math.atan2(dy, dx))
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, gr, bl, 0.35 * power)
        beamStrip(magic.laserShape, reach, sy * 1.8, frameAt)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(r * 0.75, gr * 0.6, bl * 0.9, 1)
        beamStrip(magic.laserShape, reach, sy, frameAt)
        love.graphics.setColor(lr, lg, lb, 1)
        beamStrip(magic.laserCore, reach, sy, frameAt)
        setWhite()
        beamStrip(magic.laserCore, reach, sy * 0.5, frameAt)
        -- the flash at its mouth as it fires, and the beam splashing on the wall
        if b.t < BEAM_GROW * 2 then
            love.graphics.setColor(lr, lg, lb, 1)
            beamPiece(magic.laserShape, 2, 0, 12, -4, sy)
            setWhite()
            beamPiece(magic.laserCore, 2, 0, 12, -4, sy * 0.8)
        end
        if grown >= 1 and whole then
            local flare = sy * (0.6 + math.random() * 0.4)
            love.graphics.setColor(lr, lg, lb, 1)
            beamPiece(magic.laserShape, 2, 0, 12, len + 4, flare, -1)
            setWhite()
            beamPiece(magic.laserCore, 2, 0, 12, len + 4, flare * 0.8, -1)
        end
        love.graphics.pop()
        if grown < 1 or not whole then return end

        -- lightning crawling along it, and forks leaping off: a coloured glow
        -- under each bolt, then the bolt itself, white-hot
        love.graphics.setBlendMode("add")
        love.graphics.setLineJoin("bevel")
        for pass = 1, 2 do
            love.graphics.setLineWidth(pass == 1 and 3 or 1)
            for i, line in ipairs(b.bolts) do
                if pass == 1 then love.graphics.setColor(r, gr, bl, 0.45 * power)
                elseif i == 1 then love.graphics.setColor(1, 1, 1, power)
                else love.graphics.setColor(0.8, 0.9, 1, 0.9 * power) end
                love.graphics.line(line)
            end
            for _, line in ipairs(b.forks) do
                if pass == 1 then love.graphics.setColor(r, gr, bl, 0.4 * power) else love.graphics.setColor(0.9, 0.95, 1, 0.9 * power) end
                love.graphics.line(line)
            end
        end
        love.graphics.setLineWidth(1)

        -- a glow where it strikes, and sparks flying off
        local half = b.width * 0.5
        love.graphics.setColor(r, gr, bl, 0.6 * power)
        love.graphics.circle("fill", b.x2, b.y2, half * 1.8 + math.random() * 3)
        love.graphics.setColor(1, 1, 1, 0.9 * power)
        for _ = 1, 4 do
            local a = math.random() * math.pi * 2
            local out = half + math.random() * 10
            love.graphics.line(b.x2, b.y2, b.x2 + math.cos(a) * out, b.y2 + math.sin(a) * out)
        end
        love.graphics.setBlendMode("alpha")
    end

    function g:destroy()
        if self.physics then
            self.physics:destroy()
            self.physics = nil
        end
    end

    return g
end
