-- The Demon General, who leads the demon legions: a mega boss who roams the Forest
-- Clearing (src/levels/roamingBoss.lua puts him where the map's "Boss" layer says).
--
-- A towering knight wreathed in crimson flame, with a greatsword
-- (sprites/enemies/demonLord; the art faces right, and he turns to face the
-- way he goes). Left alone, he strolls about his patch of the map and pays the
-- hero no mind. Come close to him, or strike him, and he turns: a roar, his
-- flames flare up, and he fights to the end. He stalks the hero, and:
--   thrusts his sword ahead, close up;
--   swings a crimson crescent that flies across the hall (two, later on);
--   leaps high and crashes down where the hero stood (a red ring marks the
--     spot), and the landing sends a shockwave over the floor;
--   charges across the hall sword first (a red streak shows which way).
-- At half health he erupts in hellfire (his Special): faster and harder from
-- then on, and pillars of fire burst out of the floor around the hero (a ring
-- glows on each spot first). Roll or Shadow Step through it all.
-- His sword can be met with the hero's (src/utilities/combat.lua): the thrust
-- and the crescents clash on a well-timed swing (a white glint warns of them),
-- and a clash leaves him reeling. The leap, the shockwave, the charge and the
-- hellfire can only be dodged (a red glint).
-- Enough damage in a short while staggers him, and breaks off whatever he was
-- winding up. Beaten, he crumbles to ash.
--
-- Like Gula, he is not in the `enemies` list: his collider uses the 'Enemy'
-- class with `parent` set to this table, so every weapon hits him.

local FRAME_W, FRAME_H = 216, 168
local ORIGIN_X, ORIGIN_Y = 85, 168  -- his feet, in a frame
local SCALE = 0.5
local HEIGHT = 62                   -- feet to horns, drawn
local FEET = 6                      -- his collider's middle sits this far above his feet
local MAX_HEALTH = 160
local ENRAGE_AT = 0.5               -- share of health left when the hellfire wakes
local STAGGER_TIME = 3              -- damage counts towards a stagger for this long
local WAVE_SQUASH = 0.6             -- the shockwave spreads over the floor: a flat ellipse
local LEAP_HEIGHT = 80
local AGGRO_RANGE = 52              -- this close, and he turns on the hero
local ROAM_SPEED = 16               -- strolling about, minding his own business
local FRAMES = { idle = 8, walk = 8, run = 8, attack = 8, attack2 = 8, attack3 = 8, walkAttack = 8, jump = 8,
    special = 8, hurt = 2, death = 8 }

local TAUNTS = { "Kneel.", "My legions answer to me.", "Burn in crimson fire!", "Is that all?",
    "You should have walked on by.", "Your soul will feed my flame." }

local quads = nil

-- his frames, cut once from the sheets
local function cutQuads()
    if quads then return end
    quads = {}
    for name, n in pairs(FRAMES) do
        local sheet = sprites.enemies.demonLord[name]
        quads[name] = {}
        for i = 1, n do
            quads[name][i] = love.graphics.newQuad((i - 1) * FRAME_W, 0, FRAME_W, FRAME_H, sheet:getDimensions())
        end
    end
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- frame first..last, spread evenly over `total` seconds, at `t`
local function spread(t, total, first, last)
    if total <= 0 then return last end
    return math.min(last, first + math.floor(t / total * (last - first + 1)))
end

-- roam: where he strolls while calm; arena: the whole map (his leaps and fire stay inside it)
function spawnDemonLord(x, y, roam, arena)
    local d = {}
    d.x, d.y = x, y
    d.roam = roam
    d.arena = arena
    d.maxHealth = MAX_HEALTH
    d.health = MAX_HEALTH
    d.state = "rest"
    d.timer = 1 + math.random() * 2
    d.t = 0                -- time in the current state
    d.anim = 0             -- free-running clock for looping animations
    d.facing = -1          -- 1 right, -1 left
    d.z = 0                -- height off the floor (the leap)
    d.flashTimer = 0
    d.stunTimer, d.dizzyTimer = 0, 0
    d.hitCooldown = 0
    d.poise, d.poiseTimer = 0, 0
    d.burnTicks, d.burnTimer = 0, 0
    d.hookable = false
    d.invulnerable = false
    d.noContactDamage = true -- calm, bumping into him is harmless
    d.fighting = false
    d.enraged = false
    d.dead = false
    d.boss = true          -- his hits stagger the hero (player:hurt)
    d.strikeOffset = -24   -- where the Storm Staff's lightning meets him (his chest)
    d.tauntTimer = 7
    d.lastAction = nil
    d.waves = {}           -- crimson crescents in flight
    d.rings = {}           -- the landing's shockwave
    d.pillars = {}         -- hellfire, warning then burning
    d.puffs = {}           -- smoke where a crescent breaks
    d.embers = {}

    d.physics = world:newBSGRectangleCollider(x - 11, y - FEET - 6, 22, 12, 4)
    d.physics:setCollisionClass('Enemy')
    d.physics:setFixedRotation(true)
    d.physics:setLinearDamping(8)
    d.physics:setMass(40)
    d.physics.parent = d

    cutQuads()

    ----------------------------------------------------------------- helpers

    -- normal, or enraged
    function d:value(normal, enraged)
        return self.enraged and enraged or normal
    end

    function d:feet()
        return self.x, self.y + FEET
    end

    function d:toPlayer()
        local fx, fy = self:feet()
        local dx, dy = player:getX() - fx, player:getY() - fy
        local dist = math.max(0.001, math.sqrt(dx * dx + dy * dy))
        return dx / dist, dy / dist, dist
    end

    function d:faceHero()
        if player:getX() < self.x - 2 then self.facing = -1 elseif player:getX() > self.x + 2 then self.facing = 1 end
    end

    function d:say(text, color, big)
        floatTexts:spawn(self.x, self.y - HEIGHT - 6, text, color or {1, 0.45, 0.45}, { big = big, life = 1.7 })
    end

    function d:inArena(x, y, margin)
        local a = self.arena
        return clamp(x, a.x + margin, a.x + a.w - margin), clamp(y, a.y + margin, a.y + a.h - margin)
    end

    function d:enter(state, timer)
        self.state = state
        self.t = 0
        self.timer = timer or 0
        self.glinted = false
    end

    -- the blade, held out in front of him (where his glints flash, and his blows come from)
    function d:blade()
        local fx, fy = self:feet()
        return fx + self.facing * 26, fy - 30 - self.z
    end

    -- a moment before a wind-up ends, the warning glint: white can be clashed, red only dodged
    function d:glintBefore(kind)
        if not self.glinted and self.t >= self.timer - 0.28 then
            self.glinted = true
            local x, y = self:blade()
            if kind == "dodge" then x, y = self.x, self.y - HEIGHT + 8 - self.z end
            combat:glint(x, y, kind)
        end
    end

    function d:stop()
        self.physics:setLinearVelocity(0, 0)
    end

    -- a blow at the hero: his sword (parryable) or not. "hit", "clash", "evaded" or nil
    function d:strikeHero(amount, fromX, fromY, parryable, attacker)
        amount = amount + self:value(0, 0.5)
        if parryable then return combat:melee(attacker, amount, fromX, fromY, true) end
        return combat:unblockable(amount, fromX, fromY, true)
    end

    -- the hero's sword meets his thrust (src/utilities/combat.lua)
    function d:striking()
        return self.state == "thrust" and self.t < 0.2
    end

    -- blade on blade: he reels back, his thrust spent
    function d:onClash(dir)
        if self.state == "dying" then return end
        self.physics:setSensor(false)
        self.z = 0
        self:enter("hurt", 0.5)
        self.physics:setLinearVelocity(dir.x * 70, dir.y * 70)
        self.poise = 0
    end

    ----------------------------------------------------------------- the fight

    -- calm: off to another spot in his patch (or a while standing about)
    function d:stroll()
        local r = self.roam
        self.goalX = r.x + 10 + math.random() * math.max(0, r.w - 20)
        self.goalY = r.y + 10 + math.random() * math.max(0, r.h - 20)
        self:enter("roam", 6)
    end

    function d:rest()
        self:stop()
        self.walking = false
        self:enter("rest", 1.5 + math.random() * 2.5)
    end

    -- the hero came too close, or struck him: he turns on them, roaring, his flames flaring
    function d:aggro()
        if self.fighting or self.state == "dying" then return end
        self.fighting = true
        self.noContactDamage = false
        self.walking = false
        self:faceHero()
        self:stop()
        self.casting = "roar"
        self:enter("special", 1)
        self:say("You dare?!", {1, 0.35, 0.3}, true)
        shake:start(0.5, 3, 0.03)
        dj.play("sounds/enemies/gulaThunder.wav", "static", "effect", 0.8, 0.7)
        if roamingBoss then roamingBoss:onAggro(self) end
    end

    -- walk towards the hero for a while, then choose what to do
    function d:stalk(seconds)
        self:enter("stalk", seconds or self:value(0.7 + math.random() * 0.6, 0.35 + math.random() * 0.4))
    end

    function d:chooseAction()
        local _, _, dist = self:toPlayer()
        local options
        if dist < 46 then
            options = { "thrust", "thrust", "thrust", "crescent", "leap" }
        else
            options = { "crescent", "crescent", "leap", "leap", "charge" }
            if dist > 110 then table.insert(options, "charge") end
        end
        if self.enraged then
            table.insert(options, "hellfire")
            table.insert(options, "hellfire")
        end
        local pick
        for _ = 1, 5 do
            pick = options[math.random(#options)]
            if pick ~= self.lastAction then break end
        end
        self.lastAction = pick
        self:faceHero()
        self:stop()
        if pick == "thrust" then
            self:enter("thrustWind", self:value(0.5, 0.32))
        elseif pick == "crescent" then
            -- enraged, he cuts twice: two crescents
            self.double = self.enraged
            self:enter("crescentWind", self:value(0.6, 0.38))
        elseif pick == "leap" then
            self:enter("leapWind", self:value(0.45, 0.3))
        elseif pick == "charge" then
            local dx, dy = self:toPlayer()
            self.chargeX, self.chargeY = dx, dy
            self:enter("chargeWind", self:value(0.55, 0.38))
            self:say("Hrrah!", {1, 0.4, 0.4})
        else
            self:enter("special", 0.95)
            self.casting = "hellfire"
            self:say("Burn!", {1, 0.35, 0.3}, true)
        end
    end

    -- the thrust lands: the sword reaches out in front of him
    function d:thrust()
        dj.play(sounds.items.sword, "static", "effect", 1, 0.55)
        local fx, fy = self:feet()
        local dx = (player:getX() - fx) * self.facing
        local dy = player:getY() - fy
        if dx > -6 and dx < 58 and math.abs(dy) < 16 then
            local bx, by = self:blade()
            self:strikeHero(1, bx, by + 24, true, self)
        end
    end

    -- a crimson crescent flies off his sword towards the hero
    function d:crescent()
        local dx, dy = self:toPlayer()
        local speed = self:value(150, 185)
        local fx, fy = self:feet()
        table.insert(self.waves, { x = fx + dx * 14, y = fy + dy * 8, vx = dx * speed, vy = dy * speed, life = 3, t = 0 })
        dj.play(sounds.items.sword, "static", "effect", 1, 0.4)
        dj.play(sounds.enemies.projectile, "static", "effect", 0.7, 0.5)
        shake:start(0.1, 1.5, 0.02)
    end

    -- off the floor: he follows the hero through the air, then the spot locks
    function d:leap()
        self:enter("leap", self:value(0.8, 0.62))
        self.airTime = self.timer
        local fx, fy = self:feet()
        self.leapFromX, self.leapFromY = fx, fy
        self.targetX, self.targetY = self:inArena(player:getX(), player:getY(), 26)
        self.physics:setSensor(true)
        self.noContactDamage = true
        dj.play(sounds.player.roll, "static", "effect", 1, 0.45)
    end

    -- the crash: right underneath hurts most, and the shockwave rolls outwards
    function d:land()
        self.z = 0
        self.physics:setSensor(false)
        self.noContactDamage = false
        local fx, fy = self:feet()
        if distanceBetween(fx, fy, player:getX(), player:getY()) < 22 then
            self:strikeHero(1.5, fx, fy, false)
        end
        for i = 0, self:value(0, 1) do
            table.insert(self.rings, { x = fx, y = fy, r = 6, delay = i * 0.3, speed = self:value(150, 175), max = self:value(90, 110) })
        end
        for _ = 1, 3 do
            table.insert(self.puffs, { x = fx + (math.random() - 0.5) * 30, y = fy + (math.random() - 0.5) * 10, t = 0, scale = 0.5 })
        end
        effects:spawn("scorch", fx, fy)
        shake:start(0.4, 4, 0.03)
        dj.play(sounds.items.explosion, "static", "effect", 0.9, 0.6)
        dj.play("sounds/enemies/gulaNova.wav", "static", "effect", 0.6, 0.7)
        self:enter("land", 0.3)
    end

    function d:startCharge()
        self:enter("charge", self:value(0.75, 0.85))
        self.chargeHit = false
        dj.play(sounds.player.roll, "static", "effect", 1, 0.5)
    end

    -- hellfire: a ring glows on each spot, then a pillar of fire bursts out of it
    function d:hellfire()
        local spots = { { player:getX(), player:getY() } }
        for i = 1, 4 do
            local a = math.random() * math.pi * 2
            local r = 26 + math.random() * 44
            table.insert(spots, { player:getX() + math.cos(a) * r, player:getY() + math.sin(a) * r * 0.7 })
        end
        for i, s in ipairs(spots) do
            local x, y = self:inArena(s[1], s[2], 14)
            table.insert(self.pillars, { x = x, y = y, t = -(i - 1) * 0.12, warn = 0.8, burn = 0.6 })
        end
        dj.play("sounds/enemies/gulaCharge.wav", "static", "effect", 0.8, 0.7)
    end

    -- at half health: the hellfire wakes (his Special), and he's faster and harder from then on
    function d:enrage()
        self.enraged = true
        self.invulnerable = true
        self.casting = "enrage"
        self:stop()
        self:enter("special", 1.4)
        self:say("ENOUGH! Behold my true flame!", {1, 0.3, 0.25}, true)
        shake:start(0.8, 4, 0.03)
        dj.play("sounds/enemies/gulaThunder.wav", "static", "effect", 1, 0.6)
        if roamingBoss then roamingBoss:onEnrage() end
    end

    function d:stagger()
        self.poise = 0
        self.physics:setSensor(false)
        self.noContactDamage = false
        self.z = 0
        self:stop()
        self:enter("hurt", 0.6)
        self:say("Grr...!", {1, 0.6, 0.5})
    end

    function d:die()
        self.fighting = false
        self.invulnerable = true
        self.noContactDamage = true
        self.physics:setSensor(true)
        self.z = 0
        self:stop()
        self.waves, self.rings, self.pillars = {}, {}, {}
        self:enter("dying", 1.9)
        self:say("Impossible... the sins... will rise... again...", {1, 0.45, 0.45}, true)
        shake:start(0.6, 3, 0.03)
        dj.play(sounds.enemies.die, "static", "effect", 1, 0.5)
        dj.play("sounds/enemies/gulaNova.wav", "static", "effect", 0.8, 0.5)
    end

    function d:hit(damage, dir, stun, dizziness, element)
        if not self.fighting and damage > 0 then self:aggro() end
        if self.invulnerable or not self.fighting or self.z > 20 then
            if self.fighting and damage > 0 then self.flashTimer = 0.05 end
            return
        end
        if damage <= 0 then return end
        if self.hitCooldown > 0 and damage < 3 then return end
        self.hitCooldown = 0.15
        globalStun = 0.03
        shake:start(0.08, 1, 0.02)
        dj.play(sounds.enemies.hurt, "static", "effect", 1, 0.5 + math.random() * 0.15)
        self:takeDamage(damage, dir or vector(0, 1))
    end

    function d:takeDamage(amount, dir)
        self.health = math.max(0, self.health - amount)
        self.flashTimer = 0.15
        for _ = 1, 10 do
            effects:spawn("damage", self.x, self.y - 26, { dir = dir })
        end
        if self.health <= 0 then return self:die() end
        if not self.enraged and self.health <= self.maxHealth * ENRAGE_AT then return self:enrage() end
        self.poise = self.poise + amount
        self.poiseTimer = STAGGER_TIME
        local open = self.state == "stalk" or self.state == "recover" or self.state:sub(-4) == "Wind"
        if open and self.poise >= self:value(14, 20) then self:stagger() end
    end

    function d:burn()
        if self.invulnerable then return end
        self.burnTicks = 3
        self.burnTimer = 0.5
    end

    ----------------------------------------------------------------- update

    function d:updateShots(dt)
        for i = #self.waves, 1, -1 do
            local w = self.waves[i]
            w.x, w.y = w.x + w.vx * dt, w.y + w.vy * dt
            w.t = w.t + dt
            w.life = w.life - dt
            local gone = w.life <= 0 or #world:queryCircleArea(w.x, w.y, 3, {'Wall'}) > 0
            if not gone and distanceBetween(w.x, w.y, player:getX(), player:getY()) < 12 then
                -- a sword wave: a swing can shatter it
                local r = self:strikeHero(1, w.x, w.y, true, nil)
                if r == "hit" or r == "clash" then gone = true end
            end
            if gone then
                table.insert(self.puffs, { x = w.x, y = w.y - 10, t = 0, scale = 0.4 })
                table.remove(self.waves, i)
            end
        end
        for i = #self.rings, 1, -1 do
            local r = self.rings[i]
            if r.delay > 0 then
                r.delay = r.delay - dt
            else
                r.r = r.r + r.speed * dt
                if not r.hit then
                    -- the wave is a flat ellipse on the floor: it hits where it is drawn
                    local dx, dy = player:getX() - r.x, (player:getY() - r.y) / WAVE_SQUASH
                    if math.abs(math.sqrt(dx * dx + dy * dy) - r.r) < 5 and self:strikeHero(1, r.x, r.y, false) == "hit" then r.hit = true end
                end
                if r.r > r.max then table.remove(self.rings, i) end
            end
        end
        for i = #self.pillars, 1, -1 do
            local p = self.pillars[i]
            local was = p.t
            p.t = p.t + dt
            if was < p.warn and p.t >= p.warn then
                -- it erupts
                dj.play(sounds.items.fire, "static", "effect", 0.8, 0.6 + math.random() * 0.2)
                shake:start(0.12, 1.5, 0.02)
                for _ = 1, 8 do effects:spawn("ember", p.x, p.y - 6, { scale = 1.3 }) end
            end
            if p.t >= p.warn and p.t < p.warn + p.burn and not p.hit then
                local dx, dy = player:getX() - p.x, (player:getY() - p.y) / 0.7
                if dx * dx + dy * dy < 13 * 13 and self:strikeHero(1, p.x, p.y, false) == "hit" then p.hit = true end
            end
            if p.t >= p.warn + p.burn then table.remove(self.pillars, i) end
        end
        for i = #self.puffs, 1, -1 do
            local p = self.puffs[i]
            p.t = p.t + dt
            if p.t >= 0.06 * 8 then table.remove(self.puffs, i) end
        end
    end

    function d:update(dt)
        if self.dead then return end
        self.x, self.y = self.physics:getPosition()
        self.anim = self.anim + dt * self:value(1, 1.25)
        self.t = self.t + dt
        if self.flashTimer > 0 then self.flashTimer = self.flashTimer - dt end
        if self.hitCooldown > 0 then self.hitCooldown = self.hitCooldown - dt end
        if self.poiseTimer > 0 then
            self.poiseTimer = self.poiseTimer - dt
            if self.poiseTimer <= 0 then self.poise = 0 end
        end
        self:updateShots(dt)

        if self.burnTicks > 0 then
            self.burnTimer = self.burnTimer - dt
            if math.random() < dt * 20 then effects:spawn("enemyEmber", self.x, self.y - 20, { scale = 0.7 }) end
            if self.burnTimer <= 0 then
                self.burnTicks = self.burnTicks - 1
                self.burnTimer = 0.5
                if not self.invulnerable and self.health > 0 then self:takeDamage(0.5, vector(0, -1)) end
            end
        end
        -- his flames shed embers
        if math.random() < dt * self:value(6, 14) then
            effects:spawn("enemyEmber", self.x + (math.random() - 0.5) * 16, self.y - 20 - math.random() * 30 - self.z, { scale = 0.6 })
        end

        local s = self.state
        if s == "dying" then
            self:stop()
            if self.t >= self.timer then
                self.dead = true
                self.physics:destroy()
                self.physics = nil
                if roamingBoss then roamingBoss:onDefeated(self) end
            end
            return
        elseif s == "rest" or s == "roam" then
            local _, _, dist = self:toPlayer()
            if dist < AGGRO_RANGE and not isPlayerFrozen() then return self:aggro() end
            if s == "rest" then
                self:stop()
                if self.t >= self.timer then self:stroll() end
            else
                local fx, fy = self:feet()
                local dx, dy = self.goalX - fx, self.goalY - fy
                local d2 = math.sqrt(dx * dx + dy * dy)
                if d2 < 4 or self.t >= self.timer then
                    self:rest()
                else
                    self.physics:setLinearVelocity(dx / d2 * ROAM_SPEED, dy / d2 * ROAM_SPEED)
                    if math.abs(dx) > 1 then self.facing = dx < 0 and -1 or 1 end
                    self.walking = true
                end
            end
        elseif s == "stalk" then
            self:faceHero()
            local dx, dy, dist = self:toPlayer()
            local speed = self:value(30, 44)
            if dist > 30 then self.physics:setLinearVelocity(dx * speed, dy * speed) else self:stop() end
            self.walking = dist > 30
            if self.t >= self.timer then self.walking = false; self:chooseAction() end
        elseif s == "recover" or s == "land" or s == "hurt" then
            self:stop()
            if self.t >= self.timer then
                if s == "land" then self:enter("recover", self:value(0.45, 0.2)) else self:stalk() end
            end
        elseif s == "thrustWind" then
            self:stop()
            self:glintBefore("parry")
            if self.t >= self.timer then self:enter("thrust", 5 * 0.07); self.struck = false end
        elseif s == "thrust" then
            -- the sword lunges out on the strike's first frame
            local push = self.t < 0.12 and 60 * self.facing or 0
            self.physics:setLinearVelocity(push, 0)
            if not self.struck then self.struck = true; self:thrust() end
            if self.t >= self.timer then self:enter("recover", self:value(0.5, 0.25)) end
        elseif s == "crescentWind" then
            self:stop()
            self:faceHero()
            self:glintBefore("parry")
            if self.t >= self.timer then
                self:enter("crescent", self.double and 0.62 or 0.36)
                self.cuts = 0
            end
        elseif s == "crescent" then
            self:stop()
            -- one crescent as the blade comes down, and (enraged) another on the backswing
            if self.cuts == 0 then self.cuts = 1; self:crescent() end
            if self.double and self.cuts == 1 and self.t >= 0.26 then
                self.cuts = 2
                self:faceHero()
                self:crescent()
            end
            if self.t >= self.timer then self:enter("recover", self:value(0.55, 0.25)) end
        elseif s == "leapWind" then
            self:stop()
            self:glintBefore("dodge")
            if self.t >= self.timer then self:leap() end
        elseif s == "leap" then
            -- up, and over to the hero: the spot follows them until the last moment
            local p = math.min(1, self.t / self.airTime)
            if p < 0.65 then self.targetX, self.targetY = self:inArena(player:getX(), player:getY(), 26) end
            local fx = self.leapFromX + (self.targetX - self.leapFromX) * p
            local fy = self.leapFromY + (self.targetY - self.leapFromY) * p
            self.physics:setPosition(fx, fy - FEET)
            self.physics:setLinearVelocity(0, 0)
            self.z = LEAP_HEIGHT * math.sin(p * math.pi)
            self.facing = self.targetX < self.leapFromX and -1 or 1
            if p >= 1 then self:land() end
        elseif s == "chargeWind" then
            self:stop()
            self.facing = self.chargeX < 0 and -1 or 1
            self:glintBefore("dodge")
            if self.t >= self.timer then self:startCharge() end
        elseif s == "charge" then
            local speed = self:value(230, 280)
            self.physics:setLinearVelocity(self.chargeX * speed, self.chargeY * speed)
            local fx, fy = self:feet()
            if not self.chargeHit and distanceBetween(fx, fy - 8, player:getX(), player:getY()) < 20
                and self:strikeHero(1, fx, fy, false) == "hit" then
                self.chargeHit = true
            end
            if self.t >= self.timer or self.physics:enter('Wall') then
                self:stop()
                shake:start(0.15, 2, 0.02)
                self:enter("recover", self:value(0.6, 0.3))
            end
        elseif s == "special" then
            self:stop()
            if self.casting == "hellfire" then self:glintBefore("dodge") end
            -- the flames burst on its third frame
            if not self.cast and self.t >= self.timer * 0.25 then
                self.cast = true
                if self.casting == "hellfire" then self:hellfire() end
            end
            if self.t >= self.timer then
                self.cast = false
                if self.casting == "enrage" then self.invulnerable = false end
                self.casting = nil
                self:enter("recover", self:value(0.4, 0.2))
            end
        end

        if self.fighting then
            self.tauntTimer = self.tauntTimer - dt
            if self.tauntTimer <= 0 then
                self.tauntTimer = self:value(8, 5) + math.random() * 4
                self:say(TAUNTS[math.random(#TAUNTS)])
            end
        end
    end

    ----------------------------------------------------------------- draw

    -- which sheet and frame he shows now
    function d:frame()
        local s, t = self.state, self.t
        local loop = function(name, step) return name, 1 + math.floor(self.anim / step) % FRAMES[name] end
        if s == "rest" or s == "recover" then return loop("idle", 0.12) end
        if s == "roam" then return loop("walk", 0.13) end
        if s == "stalk" then
            if self.walking then return loop("walk", self:value(0.1, 0.08)) end
            return loop("idle", 0.12)
        end
        if s == "thrustWind" then return "attack", spread(t, self.timer, 1, 3) end
        if s == "thrust" then return "attack", spread(t, self.timer, 4, 8) end
        if s == "crescentWind" then return self.double and "attack3" or "attack2", spread(t, self.timer, 1, self.double and 2 or 4) end
        if s == "crescent" then
            if self.double then return "attack3", spread(t, self.timer, 3, 8) end
            return "attack2", spread(t, self.timer, 5, 8)
        end
        if s == "leapWind" then return "jump", spread(t, self.timer, 1, 3) end
        if s == "leap" then return "jump", 4 + math.floor(t / 0.08) % 2 end
        if s == "land" then return "jump", spread(t, self.timer, 6, 8) end
        if s == "chargeWind" then return "run", 1 end
        if s == "charge" then return loop("run", 0.06) end
        if s == "special" then return "special", spread(t, self.timer, 1, 8) end
        if s == "hurt" then return "hurt", 1 + math.floor(t / 0.08) % 2 end
        if s == "dying" then return "death", spread(t, self.timer, 1, 8) end
        return loop("idle", 0.12)
    end

    function d:drawGround()
        pixelfx.world(function()
            local fx, fy = self:feet()
            -- his shadow (smaller and fainter, the higher he leaps)
            local lift = 1 - self.z / LEAP_HEIGHT * 0.5
            love.graphics.setColor(0, 0, 0, 0.4 * lift)
            love.graphics.ellipse("fill", fx, fy, 16 * lift, 5 * lift)
            -- where the leap will land
            if self.state == "leap" then
                local p = math.min(1, self.t / self.airTime)
                local pulse = 0.5 + 0.5 * math.sin(self.t * 24)
                love.graphics.setColor(1, 0.15, 0.15, 0.25 + 0.35 * p)
                love.graphics.ellipse("fill", self.targetX, self.targetY, 22 * (1.4 - 0.4 * p), 22 * (1.4 - 0.4 * p) * WAVE_SQUASH)
                love.graphics.setColor(1, 0.4, 0.3, 0.6 + 0.4 * pulse)
                love.graphics.setLineWidth(1)
                love.graphics.ellipse("line", self.targetX, self.targetY, 22, 22 * WAVE_SQUASH)
            end
            -- which way the charge goes
            if self.state == "chargeWind" then
                local p = math.min(1, self.t / self.timer)
                local len = 40 + 140 * p
                love.graphics.push()
                love.graphics.translate(fx, fy - 4)
                love.graphics.rotate(math.atan2(self.chargeY, self.chargeX))
                love.graphics.setColor(1, 0.15, 0.15, 0.18 + 0.25 * p)
                love.graphics.rectangle("fill", 0, -7, len, 14)
                love.graphics.setColor(1, 0.45, 0.35, 0.35 + 0.4 * p)
                love.graphics.rectangle("fill", 0, -1, len, 2)
                love.graphics.pop()
            end
            -- hellfire about to burst: a ring tightening on each spot
            for _, p in ipairs(self.pillars) do
                if p.t > 0 and p.t < p.warn then
                    local k = p.t / p.warn
                    love.graphics.setColor(0.9, 0.1, 0.15, 0.2 + 0.3 * k)
                    love.graphics.ellipse("fill", p.x, p.y, 13, 13 * 0.7)
                    love.graphics.setColor(1, 0.35, 0.3, 0.5 + 0.5 * k)
                    love.graphics.ellipse("line", p.x, p.y, 13 + 10 * (1 - k), (13 + 10 * (1 - k)) * 0.7)
                end
            end
            setWhite()
        end)
    end

    function d:draw()
        if self.dead then return end
        local name, f = self:frame()
        local fx, fy = self:feet()
        local shakeX = 0
        if self.state:sub(-4) == "Wind" or (self.state == "special" and self.casting == "enrage") then
            shakeX = (math.random() - 0.5) * 1.5
        end
        -- the hellfire's aura behind him
        if self.enraged and self.state ~= "dying" then
            local pulse = 0.5 + 0.5 * math.sin(self.anim * 8)
            pixelfx.world(function()
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 0.1, 0.15, 0.18 + 0.12 * pulse)
                love.graphics.ellipse("fill", fx, fy - 26 - self.z, 26 + pulse * 3, 36 + pulse * 3)
                love.graphics.setBlendMode("alpha")
            end)
        end
        if self.flashTimer > 0 then love.graphics.setShader(shaders.whiteout) end
        setWhite()
        love.graphics.draw(sprites.enemies.demonLord[name], quads[name][f], math.floor(fx + shakeX + 0.5), math.floor(fy - self.z + 0.5),
            0, SCALE * self.facing, SCALE, ORIGIN_X, ORIGIN_Y)
        love.graphics.setShader()
    end

    -- crimson crescents in flight, the shockwave, the hellfire and the smoke
    function d:drawAir()
        pixelfx.world(function()
            love.graphics.setBlendMode("add")
            for _, r in ipairs(self.rings) do
                if r.delay <= 0 then
                    local fade = 1 - r.r / r.max
                    love.graphics.setLineWidth(3)
                    love.graphics.setColor(1, 0.2, 0.2, 0.6 * fade)
                    love.graphics.ellipse("line", r.x, r.y, r.r, r.r * WAVE_SQUASH)
                    love.graphics.setLineWidth(1)
                    love.graphics.setColor(1, 0.8, 0.7, 0.8 * fade)
                    love.graphics.ellipse("line", r.x, r.y, r.r - 1, (r.r - 1) * WAVE_SQUASH)
                end
            end
            love.graphics.setBlendMode("alpha")
        end)
        -- hellfire pillars: the magic pack's flame, tinted crimson and tall
        for _, p in ipairs(self.pillars) do
            if p.t >= p.warn then
                local k = (p.t - p.warn) / p.burn
                local grow = math.min(1, k * 5) * (1 - math.max(0, k - 0.75) * 4)
                local frame = 1 + math.floor(p.t / 0.07) % 4
                love.graphics.setColor(1, 0.35, 0.4, 1)
                love.graphics.draw(sprites.effects.magic.flame, sprites.effects.magicQuads.flame[frame], p.x, p.y + 2, 0, 1.7, 1.5 * grow, 36, 42)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 0.25, 0.3, 0.7)
                love.graphics.draw(sprites.effects.magic.flame, sprites.effects.magicQuads.flame[frame], p.x, p.y + 2, 0, 1.2, 1.2 * grow, 36, 42)
                love.graphics.setBlendMode("alpha")
            end
        end
        pixelfx.world(function()
            for _, w in ipairs(self.waves) do
                local a = math.atan2(w.vy, w.vx)
                local y = w.y - 10
                love.graphics.setColor(0, 0, 0, 0.25)
                love.graphics.ellipse("fill", w.x, w.y, 9, 3)
                love.graphics.setBlendMode("add")
                love.graphics.setLineWidth(3)
                love.graphics.setColor(1, 0.12, 0.25, 0.85)
                love.graphics.arc("line", "open", w.x - math.cos(a) * 6, y - math.sin(a) * 6, 14, a - 1.25, a + 1.25, 14)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(1, 0.85, 0.85, 1)
                love.graphics.arc("line", "open", w.x - math.cos(a) * 4, y - math.sin(a) * 4, 12, a - 1.05, a + 1.05, 12)
                love.graphics.setBlendMode("alpha")
            end
            setWhite()
        end)
        local sheet, frames = sprites.effects.magic.smokeBurst, sprites.effects.magicQuads.smokeBurst
        for _, p in ipairs(self.puffs) do
            love.graphics.setColor(0.55, 0.25, 0.3, 0.85)
            love.graphics.draw(sheet, frames[math.min(8, 1 + math.floor(p.t / 0.06))], p.x, p.y, 0, p.scale, p.scale, 36, 36)
        end
        setWhite()
    end

    -- the fire glows through the hall's darkness (drawn after it)
    function d:drawEmissive()
        if self.dead then return end
        pixelfx.world(function()
            love.graphics.setBlendMode("add")
            local fx, fy = self:feet()
            local pulse = 0.5 + 0.5 * math.sin(self.anim * 6)
            love.graphics.setColor(1, 0.15, 0.2, self:value(0.08, 0.14) + 0.05 * pulse)
            love.graphics.ellipse("fill", fx, fy - 30 - self.z, 20, 28)
            for _, w in ipairs(self.waves) do
                love.graphics.setColor(1, 0.2, 0.3, 0.35)
                love.graphics.circle("fill", w.x, w.y - 10, 9)
            end
            for _, p in ipairs(self.pillars) do
                if p.t >= p.warn then
                    love.graphics.setColor(1, 0.2, 0.25, 0.3)
                    love.graphics.ellipse("fill", p.x, p.y - 14, 10, 20)
                end
            end
            love.graphics.setBlendMode("alpha")
            setWhite()
        end)
    end

    -- his light, and his fire's (lighting:sources)
    function d:addLights(list)
        if self.dead then return end
        local fx, fy = self:feet()
        table.insert(list, { x = fx, y = fy - 28 - self.z, radius = self:value(72, 96), color = { 1, 0.25, 0.25 }, strength = 0.9 })
        for _, w in ipairs(self.waves) do
            table.insert(list, { x = w.x, y = w.y - 10, radius = 34, color = { 1, 0.3, 0.35 }, strength = 0.8 })
        end
        for _, p in ipairs(self.pillars) do
            if p.t > 0 then
                local burning = p.t >= p.warn
                table.insert(list, { x = p.x, y = p.y - 10, radius = burning and 46 or 24, color = { 1, 0.3, 0.25 }, strength = burning and 1 or 0.5 })
            end
        end
    end

    function d:destroy()
        if self.physics then
            self.physics:destroy()
            self.physics = nil
        end
    end

    return d
end
