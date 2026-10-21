-- Rick, the very hungry boss of Willowbrook's plaza.
--
-- He hops around as a giant head, spits food, belly-flops into shockwaves,
-- charges in later phases, and keeps trying to eat the village food crates.
-- Eating a crate heals him; hitting him while he eats makes him choke.
--
-- Rick is not part of the `enemies` list. His collider uses the 'Enemy'
-- collision class with `parent` set to this table, so every weapon that hits
-- enemies (sword, arrows, bombs, fire, boomerang) works on him as well.

local RICK_SCALE = 0.85
local FRAME_CLOSED, FRAME_CHOMP, FRAME_WIDE, FRAME_DIZZY = 1, 2, 3, 4
local MOUTH_HEIGHT = 14

local TAUNTS = { "NOM!", "MINE!", "Snack time!", "Still hungry...", "Got any cheese?", "Crumbs for you!" }

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function spawnRick(x, y, arena)
    local rick = {}
    rick.boss = true -- his hits stagger the hero (player:hurt)
    rick.x = x
    rick.y = y
    rick.homeX = x
    rick.homeY = y
    rick.arena = arena
    rick.z = 0
    rick.maxHealth = 48
    rick.health = rick.maxHealth
    rick.hitCooldown = 0 -- brief invulnerability after each hit so sword spam can't melt him
    rick.phase = 1
    rick.state = "feast"
    rick.timer = 0
    rick.size = 1
    rick.squashX = 1
    rick.squashY = 1
    rick.frame = FRAME_CLOSED
    rick.chewTimer = 0
    rick.flashTimer = 0
    rick.stunTimer = 0
    rick.dizzyTimer = 0
    rick.hookable = false
    rick.invulnerable = true
    rick.noContactDamage = true
    rick.fighting = false
    rick.jitter = 0
    rick.burnTicks = 0
    rick.burnTimer = 0
    rick.eatTarget = nil
    rick.eatTimer = 0
    rick.eatDamage = 0
    rick.nomTimer = 0
    rick.sinceEat = 0
    rick.tauntTimer = 5
    rick.feastNomTimer = 1.5
    rick.lastAction = nil
    rick.crumbs = {}  -- food he spits at the player
    rick.rings = {}   -- shockwaves from belly flops
    rick.bits = {}    -- purely visual crumbs while he eats

    rick.physics = world:newBSGRectangleCollider(x - 11, y - 7, 22, 14, 5)
    rick.physics:setCollisionClass('Enemy')
    rick.physics:setFixedRotation(true)
    rick.physics:setLinearDamping(10)
    rick.physics:setMass(6)
    rick.physics.parent = rick

    ----------------------------------------------------------------- helpers

    function rick:phaseValue(a, b, c)
        if self.phase == 1 then return a end
        if self.phase == 2 then return b end
        return c
    end

    function rick:dirTo(tx, ty)
        local dx, dy = tx - self.x, ty - self.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 0.001 then return 0, 0, 0 end
        return dx / d, dy / d, d
    end

    function rick:distToPlayer()
        return distanceBetween(self.x, self.y, player:getX(), player:getY())
    end

    function rick:clampToArena(tx, ty, margin)
        if not self.arena then return tx, ty end
        margin = margin or 18
        local a = self.arena
        return clamp(tx, a.x + margin, a.x + a.w - margin), clamp(ty, a.y + margin + 6, a.y + a.h - margin)
    end

    function rick:say(text, color, big)
        floatTexts:spawn(self.x, self.y - 50 * self.size, text, color or {1, 0.85, 0.45}, {life = 1.3, rise = 10, big = big})
    end

    function rick:spawnBits(x, y, count)
        for _ = 1, count do
            local angle = math.random() * math.pi * 2
            local speed = 15 + math.random() * 30
            table.insert(self.bits, {
                x = x, y = y, z = 10 + math.random() * 6,
                vx = math.cos(angle) * speed, vy = math.sin(angle) * speed * 0.6, vz = 30 + math.random() * 40,
                life = 0.6 + math.random() * 0.4,
                color = ({{0.84, 0.58, 0.28}, {0.95, 0.80, 0.30}, {0.80, 0.22, 0.20}, {0.55, 0.75, 0.30}})[math.random(1, 4)]
            })
        end
    end

    function rick:dust(count)
        for i = 1, count do
            local angle = (i / count) * math.pi * 2
            effects:spawn("walkDust", self.x + math.cos(angle) * 8, self.y + math.sin(angle) * 4, {dir = vector(-math.cos(angle), -math.sin(angle)), scale = 0.7})
        end
    end

    ----------------------------------------------------------------- hopping

    -- hops toward whatever targetFn returns; calls done() when finished
    function rick:startHops(count, targetFn, done)
        self.state = "hop"
        self.hopsLeft = count
        self.hopTargetFn = targetFn
        self.hopDone = done
        self.hopSpeed = self:phaseValue(80, 95, 115)
        self.hopDuration = self:phaseValue(0.46, 0.40, 0.34)
        self.hopPause = 0
        self:beginHop()
    end

    function rick:beginHop()
        self.hopTimer = 0
        local tx, ty = self.hopTargetFn()
        tx, ty = self:clampToArena(tx, ty)
        local dx, dy, d = self:dirTo(tx, ty)
        local speed = math.min(self.hopSpeed, d / self.hopDuration)
        self.vx, self.vy = dx * speed, dy * speed
        self.squashX, self.squashY = 0.85, 1.2
    end

    function rick:updateHop(dt)
        if self.hopPause > 0 then
            self.hopPause = self.hopPause - dt
            self.physics:setLinearVelocity(0, 0)
            if self.hopPause <= 0 then self:beginHop() end
            return
        end

        self.hopTimer = self.hopTimer + dt
        local t = self.hopTimer / self.hopDuration
        if t < 1 then
            self.z = math.sin(t * math.pi) * 10
            self.physics:setLinearVelocity(self.vx, self.vy)
            return
        end

        self.z = 0
        self.physics:setLinearVelocity(0, 0)
        self.squashX, self.squashY = 1.2, 0.82
        self.hopsLeft = self.hopsLeft - 1
        if self.hopsLeft > 0 then
            self.hopPause = 0.08
        else
            local done = self.hopDone
            self.hopDone = nil
            if done then done() else self:idle(0.4) end
        end
    end

    ----------------------------------------------------------------- actions

    function rick:idle(seconds)
        self.state = "idle"
        self.timer = seconds or 0.6
        self.physics:setLinearVelocity(0, 0)
    end

    -- picks an attack by weight, never repeating the previous one
    function rick:pickAttack(weights)
        local total = 0
        for name, weight in pairs(weights) do
            if name ~= self.lastAction then total = total + weight end
        end
        local roll = math.random() * total
        for name, weight in pairs(weights) do
            if name ~= self.lastAction then
                roll = roll - weight
                if roll <= 0 then return name end
            end
        end
        return "hop"
    end

    function rick:startAttack(name)
        if name == "spit" then
            self:startSpitWind()
        elseif name == "slam" then
            self:startSlamCrouch()
        elseif name == "charge" then
            self:startChargeWind()
        else
            self.lastAction = "hop"
            self:startHops(self:phaseValue(2, 3, 3), function() return player:getPosition() end, function() self:followUp() end)
        end
    end

    function rick:chooseAction()
        local full = villageStory:fullCrates()

        if #full > 0 and self.sinceEat > self:phaseValue(9, 7, 5) and math.random() < self:phaseValue(0.35, 0.45, 0.55) then
            return self:startSeekFood()
        end

        if self:distToPlayer() > 110 and self.lastAction ~= "spit" then
            -- far away: either close the distance or lob food from range
            if math.random() < 0.5 then return self:startSpitWind() end
            self.lastAction = "hop"
            return self:startHops(3, function() return player:getPosition() end, function() self:followUp() end)
        end

        local weights = { spit = 30, slam = 30, hop = 20 }
        if self.phase >= 2 then weights.charge = 30 end
        self:startAttack(self:pickAttack(weights))
    end

    -- after hopping close to the player, often go straight into an attack
    function rick:followUp()
        if self:distToPlayer() < 70 and math.random() < 0.65 then
            self:startAttack(self:pickAttack({ spit = 1, slam = 1 }))
        else
            self:idle(self:phaseValue(0.5, 0.4, 0.25))
        end
    end

    function rick:startSpitWind()
        self.lastAction = "spit"
        self.state = "spitWind"
        self.timer = 0.45
        self.squashX, self.squashY = 1.15, 0.9
        self.physics:setLinearVelocity(0, 0)
    end

    function rick:spit()
        local count = self:phaseValue(3, 5, 7)
        local spread = self:phaseValue(0.7, 1.0, 1.35)
        local px, py = player:getPosition()
        local base = math.atan2(py - self.y, px - self.x)
        for i = 1, count do
            local angle = base
            if count > 1 then angle = base - spread / 2 + spread * (i - 1) / (count - 1) end
            local speed = 105 + math.random() * 20
            table.insert(self.crumbs, {
                x = self.x, y = self.y,
                vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
                life = 2.4, frame = math.random(1, 4),
                rot = math.random() * math.pi * 2, spin = (math.random() - 0.5) * 14
            })
        end
        self.squashX, self.squashY = 0.85, 1.2
        dj.play(sounds.enemies.projectile, "static", "effect", 1, 0.7)
        self.state = "recover"
        self.timer = self:phaseValue(0.7, 0.55, 0.4)
    end

    function rick:startSlamCrouch()
        self.lastAction = "slam"
        self.state = "slamCrouch"
        self.timer = 0.45
        self.squashX, self.squashY = 1.25, 0.75
        self.physics:setLinearVelocity(0, 0)
    end

    function rick:startSlamAir()
        self.state = "slamAir"
        self.slamTime = 0
        self.slamDuration = 0.8
        local tx, ty = self:clampToArena(player:getX(), player:getY())
        self.slamTargetX, self.slamTargetY = tx, ty
        self.vx = (tx - self.x) / self.slamDuration
        self.vy = (ty - self.y) / self.slamDuration
        self.squashX, self.squashY = 0.8, 1.25
        dj.play(sounds.player.roll, "static", "effect", 1, 0.6)
    end

    function rick:land()
        self.z = 0
        self.physics:setLinearVelocity(0, 0)
        self.squashX, self.squashY = 1.4, 0.65
        shake:start(0.3, 3, 0.03)
        dj.play(sounds.items.explosion, "static", "effect", 0.8, 0.55)
        self:dust(10)
        self:spawnRing(0)
        if self.phase >= 3 then self:spawnRing(0.3) end
        if self:distToPlayer() < 16 and player.state ~= 0.5 and not isPlayerFrozen() then
            player:hurt(1, self.x, self.y, true)
        end
        self.state = "recover"
        self.timer = self:phaseValue(1.0, 0.8, 0.6)
    end

    function rick:spawnRing(delay)
        table.insert(self.rings, {
            x = self.x, y = self.y, r = 6, delay = delay,
            speed = self:phaseValue(120, 135, 150), max = 115, hit = false
        })
    end

    function rick:startChargeWind()
        self.lastAction = "charge"
        self.state = "chargeWind"
        self.timer = 0.75
        self.jitter = 1.5
        self.physics:setLinearVelocity(0, 0)
        self:say("!!", {1, 0.4, 0.3}, true)
    end

    function rick:startCharge()
        self.state = "charge"
        self.timer = 1.2
        self.jitter = 0
        self.stuckTimer = 0
        self.chargeHit = false
        local dx, dy = self:dirTo(player:getX(), player:getY())
        if dx == 0 and dy == 0 then dx = 1 end
        self.chargeSpeed = self:phaseValue(230, 230, 265)
        self.vx, self.vy = dx * self.chargeSpeed, dy * self.chargeSpeed
        self.squashX, self.squashY = 1.2, 0.85
    end

    function rick:bonk()
        self.physics:setLinearVelocity(0, 0)
        self.state = "dizzy"
        self.dizzyTimer = 2.0
        shake:start(0.25, 2.5, 0.03)
        dj.play(sounds.items.explosion, "static", "effect", 0.6, 1.4)
        self:say("BONK!", {1, 0.95, 0.6}, true)
        self:dust(6)
    end

    function rick:nearestFullCrate()
        local best, bestD
        for _, crate in ipairs(villageStory:fullCrates()) do
            local d = distanceBetween(self.x, self.y, crate.x, crate.y)
            if not best or d < bestD then best, bestD = crate, d end
        end
        return best
    end

    function rick:startSeekFood(crate, scripted)
        crate = crate or self:nearestFullCrate()
        if not crate then return self:idle(0.3) end
        self.lastAction = "eat"
        self.eatTarget = crate
        self.scripted = scripted
        self.seekHops = 0
        -- eat from beside the crate so both stay visible
        local side = self.x < crate.x and -22 or 22
        self.eatSpotX, self.eatSpotY = self:clampToArena(crate.x + side, crate.y + 4)
        if not scripted then self:say("Ooh, FOOD!", {1, 0.85, 0.45}, true) end
        self.state = "seekFood"
        self:hopTowardFood()
    end

    function rick:hopTowardFood()
        local crate = self.eatTarget
        self.seekHops = self.seekHops + 1
        self:startHops(1, function() return self.eatSpotX, self.eatSpotY end, function()
            if crate.state ~= "full" then
                self.eatTarget = nil
                return self:idle(0.3)
            end
            if distanceBetween(self.x, self.y, self.eatSpotX, self.eatSpotY) < 10 or self.seekHops >= 10 then
                self:startEating()
            else
                self.state = "seekFood"
                self:hopTowardFood()
            end
        end)
        self.state = "seekFood"
    end

    function rick:startEating()
        self.state = "eat"
        self.eatTimer = self.scripted and 2.2 or self:phaseValue(3.2, 2.8, 2.4)
        self.eatDamage = 0
        self.nomTimer = 0
        self.eatTarget.biting = true
        self.physics:setLinearVelocity(0, 0)
    end

    function rick:finishEating()
        local crate = self.eatTarget
        self.eatTarget = nil
        crate:setEaten()
        self.sinceEat = 0
        self:spawnBits(crate.x, crate.y - 8, 14)
        shake:start(0.15, 1.5, 0.03)
        dj.play(sounds.enemies.hurt, "static", "effect", 1, 0.45)

        if self.scripted then
            self.scripted = false
            self:say("*BURP*", {1, 0.95, 0.7}, true)
            self:startHops(2, function() return self.homeX, self.homeY end, function() self:feast() end)
            return
        end

        local heal = self:phaseValue(6, 6, 8)
        self.health = math.min(self.maxHealth, self.health + heal)
        self.size = math.min(1.2, self.size + 0.05)
        self:say("*BURP*  +" .. heal, {0.5, 1, 0.5}, true)
        self:checkPhase(true)
        self.state = "recover"
        self.timer = 0.8
    end

    function rick:feast()
        self.state = "feast"
        self.physics:setLinearVelocity(0, 0)
    end

    ----------------------------------------------------------------- story hooks

    function rick:scriptEat(crate)
        self:startSeekFood(crate, true)
    end

    function rick:beginFight()
        self.fighting = true
        self.invulnerable = false
        self.sinceEat = 4
        self:idle(0.6)
    end

    function rick:announce(text)
        self:say(text, {1, 0.45, 0.35}, true)
        shake:start(0.3, 2, 0.03)
        dj.play(sounds.enemies.die, "static", "effect", 0.8, 0.5)
    end

    function rick:checkPhase(healing)
        local ratio = self.health / self.maxHealth
        if healing then
            -- eating can push him back up a phase
            if self.phase == 3 and ratio > 1 / 3 then self.phase = 2 end
            if self.phase == 2 and ratio > 2 / 3 then self.phase = 1 end
            return
        end
        if self.phase == 1 and ratio <= 2 / 3 then
            self.phase = 2
            self:announce("Grr... still HUNGRY!")
        elseif self.phase == 2 and ratio <= 1 / 3 then
            self.phase = 3
            self:announce("I'M... STARVING!!")
        end
    end

    function rick:defeat()
        self.state = "defeated"
        self.fighting = false
        self.invulnerable = true
        self.noContactDamage = true
        self.dizzyTimer = 0
        self.jitter = 0
        self.z = 0
        self.physics:setLinearVelocity(0, 0)
        if self.eatTarget then self.eatTarget.biting = false end
        self.eatTarget = nil
        self.crumbs = {}
        self.rings = {}
        shake:start(0.4, 3, 0.03)
        particleEvent("death", self.x, self.y - MOUTH_HEIGHT)
        dj.play(sounds.enemies.die, "static", "effect", 1, 0.6)
        villageStory:onRickDefeated()
    end

    ----------------------------------------------------------------- damage

    function rick:takeDamage(amount, dir)
        self.health = math.max(0, self.health - amount)
        self.flashTimer = 0.15
        for _ = 1, 10 do
            effects:spawn("damage", self.x, self.y - MOUTH_HEIGHT, {dir = dir})
        end

        if self.state == "eat" then
            self.eatDamage = self.eatDamage + amount
            if self.eatDamage >= self:phaseValue(3, 4, 5) then
                self.eatTarget.biting = false
                self.eatTarget = nil
                self.sinceEat = 0
                self.state = "dizzy"
                self.dizzyTimer = 2.2
                self:say("*CHOKE*", {1, 0.7, 0.4}, true)
                self:spawnBits(self.x, self.y - 6, 10)
            end
        end

        if self.health <= 0 then
            self:defeat()
        else
            self:checkPhase()
        end
    end

    -- called by every player weapon (same signature as regular enemies)
    function rick:hit(damage, dir, stun, dizziness)
        if self.invulnerable or self.state == "defeated" or self.z > 6 then return end
        dir = dir or vector(0, 1)

        if damage <= 0 then
            -- the boomerang only makes him flinch
            if dizziness and self.state ~= "charge" and self.state ~= "slamAir" then
                self.stunTimer = 0.35
            end
            self.flashTimer = 0.08
            return
        end

        -- bombs always land; quick weapons share a short cooldown
        if self.hitCooldown > 0 and damage < 3 then return end
        self.hitCooldown = 0.2

        globalStun = 0.035
        shake:start(0.08, 1, 0.02)
        dj.play(sounds.enemies.hurt, "static", "effect", 1, 0.75 + math.random() * 0.2)

        if self.state == "idle" or self.state == "recover" or self.state == "dizzy" then
            self.physics:applyLinearImpulse((dir:normalized() * 25):unpack())
        end

        self:takeDamage(damage, dir)
    end

    function rick:burn()
        if self.invulnerable then return end
        self.burnTicks = 3
        self.burnTimer = 0.5
    end

    ----------------------------------------------------------------- update

    function rick:updateCrumbs(dt)
        for i = #self.crumbs, 1, -1 do
            local c = self.crumbs[i]
            c.x = c.x + c.vx * dt
            c.y = c.y + c.vy * dt
            c.rot = c.rot + c.spin * dt
            c.life = c.life - dt
            local remove = c.life <= 0
            if not remove and #world:queryCircleArea(c.x, c.y, 2, {'Wall'}) > 0 then
                remove = true
                self:spawnBits(c.x, c.y, 3)
            end
            if not remove and not isPlayerFrozen() and player.damagedTimer <= 0
                and distanceBetween(c.x, c.y, player:getX(), player:getY()) < 7 then
                player:hurt(0.5, c.x - c.vx, c.y - c.vy, true)
                remove = true
            end
            if remove then table.remove(self.crumbs, i) end
        end

        for i = #self.rings, 1, -1 do
            local r = self.rings[i]
            if r.delay > 0 then
                r.delay = r.delay - dt
            else
                r.r = r.r + r.speed * dt
                if not r.hit and player.state ~= 0.5 and not isPlayerFrozen() and player.damagedTimer <= 0 then
                    local d = distanceBetween(r.x, r.y, player:getX(), player:getY())
                    if math.abs(d - r.r) < 5 then
                        r.hit = true
                        player:hurt(0.5, r.x, r.y, true)
                    end
                end
                if r.r > r.max then table.remove(self.rings, i) end
            end
        end

        for i = #self.bits, 1, -1 do
            local b = self.bits[i]
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.vz = b.vz - 260 * dt
            b.z = math.max(0, b.z + b.vz * dt)
            b.life = b.life - dt
            if b.life <= 0 then table.remove(self.bits, i) end
        end
    end

    function rick:updateFrame(dt)
        self.chewTimer = self.chewTimer + dt
        if self.state == "dizzy" or self.state == "defeated" then
            self.frame = FRAME_DIZZY
        elseif self.state == "eat" then
            self.frame = ({FRAME_CHOMP, FRAME_WIDE, FRAME_CHOMP, FRAME_CLOSED})[math.floor(self.chewTimer / 0.1) % 4 + 1]
        elseif self.state == "feast" then
            self.frame = ({FRAME_CHOMP, FRAME_CLOSED})[math.floor(self.chewTimer / 0.22) % 2 + 1]
        elseif self.state == "spitWind" or self.state == "charge" or self.state == "chargeWind" then
            self.frame = FRAME_WIDE
        elseif self.state == "slamAir" then
            self.frame = FRAME_CHOMP
        else
            self.frame = FRAME_CLOSED
        end
    end

    function rick:update(dt)
        self.x, self.y = self.physics:getPosition()

        self.squashX = self.squashX + (1 - self.squashX) * math.min(1, dt * 10)
        self.squashY = self.squashY + (1 - self.squashY) * math.min(1, dt * 10)
        if self.flashTimer > 0 then self.flashTimer = self.flashTimer - dt end
        if self.hitCooldown > 0 then self.hitCooldown = self.hitCooldown - dt end
        self.sinceEat = self.sinceEat + dt

        if self.burnTicks > 0 then
            self.burnTimer = self.burnTimer - dt
            if math.random() < dt * 20 then
                effects:spawn("enemyEmber", self.x, self.y - MOUTH_HEIGHT, {scale = 0.6})
            end
            if self.burnTimer <= 0 then
                self.burnTicks = self.burnTicks - 1
                self.burnTimer = 0.5
                if self.state ~= "defeated" then self:takeDamage(0.5, vector(0, -1)) end
            end
        end

        self:updateCrumbs(dt)
        self:updateFrame(dt)

        self.noContactDamage = not self.fighting or self.z > 4 or self.state == "defeated"

        if self.stunTimer > 0 then
            self.stunTimer = self.stunTimer - dt
            self.physics:setLinearVelocity(0, 0)
            return
        end

        local s = self.state

        if s == "feast" then
            self.feastNomTimer = self.feastNomTimer - dt
            if self.feastNomTimer <= 0 then
                self.feastNomTimer = 1.6 + math.random() * 1.5
                self:say(math.random() < 0.5 and "NOM" or "nom nom", {1, 0.9, 0.6})
            end
        elseif s == "idle" then
            self.timer = self.timer - dt
            if self.timer <= 0 then self:chooseAction() end
        elseif s == "recover" then
            self.timer = self.timer - dt
            if self.timer <= 0 then self:idle(self:phaseValue(0.45, 0.3, 0.2)) end
        elseif s == "hop" or s == "seekFood" then
            self:updateHop(dt)
        elseif s == "spitWind" then
            self.timer = self.timer - dt
            if self.timer <= 0 then self:spit() end
        elseif s == "slamCrouch" then
            self.timer = self.timer - dt
            if self.timer <= 0 then self:startSlamAir() end
        elseif s == "slamAir" then
            self.slamTime = self.slamTime + dt
            local t = self.slamTime / self.slamDuration
            if t >= 1 then
                self:land()
            else
                self.z = math.sin(t * math.pi) * 48
                self.physics:setLinearVelocity(self.vx, self.vy)
            end
        elseif s == "chargeWind" then
            self.timer = self.timer - dt
            if self.timer <= 0 then self:startCharge() end
        elseif s == "charge" then
            self.timer = self.timer - dt
            local vx, vy = self.physics:getLinearVelocity()
            if math.sqrt(vx * vx + vy * vy) < self.chargeSpeed * 0.35 then
                self.stuckTimer = self.stuckTimer + dt
            else
                self.stuckTimer = 0
            end
            if self.physics:enter('Wall') or self.stuckTimer > 0.12 then
                self:bonk()
            elseif self.timer <= 0 then
                self.physics:setLinearVelocity(0, 0)
                self.state = "recover"
                self.timer = 0.5
            else
                self.physics:setLinearVelocity(self.vx, self.vy)
                if math.random() < dt * 25 then self:dust(1) end
                if not self.chargeHit and not isPlayerFrozen() and self:distToPlayer() < 15 then
                    self.chargeHit = true
                    player:hurt(1, self.x, self.y, true)
                end
            end
        elseif s == "eat" then
            self.physics:setLinearVelocity(0, 0)
            self.eatTimer = self.eatTimer - dt
            self.nomTimer = self.nomTimer - dt
            if self.eatTarget then self.eatTarget.shake = 0.1 end
            if self.nomTimer <= 0 then
                self.nomTimer = 0.8
                self:say("NOM", {1, 0.9, 0.6})
                if self.eatTarget then self:spawnBits(self.eatTarget.x, self.eatTarget.y - 10, 4) end
            end
            if self.eatTimer <= 0 then self:finishEating() end
        elseif s == "dizzy" then
            self.physics:setLinearVelocity(0, 0)
            self.dizzyTimer = self.dizzyTimer - dt
            if self.dizzyTimer <= 0 then
                self.dizzyTimer = 0
                self:idle(0.3)
            end
        elseif s == "defeated" then
            self.physics:setLinearVelocity(0, 0)
        end

        if self.fighting and s ~= "defeated" then
            self.tauntTimer = self.tauntTimer - dt
            if self.tauntTimer <= 0 then
                self.tauntTimer = 6 + math.random() * 4
                self:say(TAUNTS[math.random(1, #TAUNTS)])
            end
        end
    end

    ----------------------------------------------------------------- draw

    function rick:drawGround()
        pixelfx.world(function()
            for _, r in ipairs(self.rings) do
                if r.delay <= 0 then
                    local alpha = 1 - r.r / r.max
                    love.graphics.setLineWidth(3)
                    love.graphics.setColor(0.45, 0.30, 0.18, alpha * 0.8)
                    love.graphics.circle("line", r.x, r.y, r.r + 1.5)
                    love.graphics.setLineWidth(1.5)
                    love.graphics.setColor(1, 0.92, 0.7, alpha)
                    love.graphics.circle("line", r.x, r.y, r.r)
                end
            end
            love.graphics.setLineWidth(1)

            -- landing marker while he is in the air
            if self.state == "slamAir" then
                local t = self.slamTime / self.slamDuration
                local radius = 18 - 6 * t
                love.graphics.setColor(0.85, 0.15, 0.1, 0.25 + 0.35 * t)
                love.graphics.ellipse("fill", self.slamTargetX, self.slamTargetY + 3, radius, radius * 0.45)
                love.graphics.setLineWidth(1.5)
                love.graphics.setColor(1, 0.35, 0.25, 0.5 + 0.5 * t)
                love.graphics.ellipse("line", self.slamTargetX, self.slamTargetY + 3, radius, radius * 0.45)
                love.graphics.setLineWidth(1)
            end

            local shadow = self.size * (1 - math.min(self.z, 60) / 110)
            love.graphics.setColor(0, 0, 0, 0.28)
            love.graphics.ellipse("fill", self.x, self.y + 3, 15 * shadow, 5 * shadow)

            for _, c in ipairs(self.crumbs) do
                love.graphics.setColor(0, 0, 0, 0.25)
                love.graphics.ellipse("fill", c.x, c.y + 2, 3, 1.2)
            end
        end)
        setWhite()
    end

    function rick:draw()
        local sx = RICK_SCALE * self.size * self.squashX
        local sy = RICK_SCALE * self.size * self.squashY
        local jx = 0
        if self.jitter > 0 then jx = (math.random() * 2 - 1) * self.jitter end

        if self.flashTimer > 0 then
            love.graphics.setShader(shaders.whiteout)
        end
        if self.burnTicks > 0 then
            love.graphics.setColor(1, 0.75, 0.55, 1)
        elseif self.phase == 3 and self.fighting then
            local pulse = 0.82 + math.sin(love.timer.getTime() * 8) * 0.08
            love.graphics.setColor(1, pulse, pulse, 1)
        else
            setWhite()
        end
        love.graphics.draw(sprites.enemies.rickSheet, sprites.enemies.rickQuads[self.frame],
            self.x + jx, self.y + 4 - self.z, 0, sx, sy, 19, 53)
        love.graphics.setShader()
        setWhite()

        if self.state == "dizzy" or self.state == "defeated" then
            local t = love.timer.getTime() * 4
            local cy = self.y + 4 - self.z - 50 * sy
            for i = 1, 3 do
                local a = t + i * (math.pi * 2 / 3)
                local px, py = self.x + math.cos(a) * 12, cy + math.sin(a) * 3
                love.graphics.setColor(1, 0.95, 0.4, 1)
                love.graphics.rectangle("fill", px - 1.5, py - 0.5, 3, 1)
                love.graphics.rectangle("fill", px - 0.5, py - 1.5, 1, 3)
            end
            setWhite()
        end
    end

    function rick:drawAir()
        for _, c in ipairs(self.crumbs) do
            love.graphics.draw(sprites.items.food, sprites.items.foodQuads[c.frame], c.x, c.y - MOUTH_HEIGHT * 0.6, c.rot, 1, 1, 4, 4)
        end
        for _, b in ipairs(self.bits) do
            love.graphics.setColor(b.color[1], b.color[2], b.color[3], math.min(1, b.life * 3))
            love.graphics.rectangle("fill", b.x - 0.75, b.y - b.z - 0.75, 1.5, 1.5)
        end
        setWhite()
    end

    function rick:destroy()
        if self.physics then
            self.physics:destroy()
            self.physics = nil
        end
    end

    return rick
end
