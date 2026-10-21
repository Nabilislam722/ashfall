enemies = {}

function spawnEnemy(x, y, type, args)

    local enemy = {}

    enemy.type = type
    enemy.key = args and args.key -- remembered in data.defeated once killed
    enemy.dead = false
    enemy.stamp = "enemy"
    enemy.health = 3
    enemy.flashTimer = 0
    enemy.stunTimer = 0
    enemy.dizzyTimer = 0
    enemy.animTimer = 0
    enemy.moving = 1
    enemy.chase = true
    enemy.debugRad = 70
    enemy.burningTimer = 0
    enemy.burningCounter = 0 -- how many remaining burn procs
    enemy.emberTimer = 0

    enemy.hookable = true
    enemy.hookVec = nil

    -- Enemy states:
    -- 0: idle, standing
    -- 1: wander, stopped
    -- 1.1: wander, moving
    -- 99: alert
    -- 100: attacking
    enemy.state = 1

    enemy.startX = x
    enemy.startY = y
    enemy.wanderRadius = 30
    enemy.wanderSpeed = 15
    enemy.wanderTimer = 0.5 + math.random()*2
    enemy.wanderBufferTimer = 0
    enemy.wanderDir = vector(1,1)

    function enemy:floatDown(dest)
        self.tween = flux.to(self, self.floatTime, {floatY = dest}):ease("sineinout"):oncomplete(function() self:floatUp(self.floatMax) end)
    end

    function enemy:floatUp(dest, start)
        local time = self.floatTime
        if start then time = math.random() end
        self.tween = flux.to(self, time, {floatY = dest}):ease("sineinout"):oncomplete(function() self:floatDown(self.floatMax*-1) end)
    end

    -- Function that sets the properties of the new enemy
    local init
    if type == "eye" then
        init = require("src/enemies/eye")
    elseif type == "bat" then
        init = require("src/enemies/bat")
    elseif type == "skeleton" then
        init = require("src/enemies/skeleton")
    elseif type == "slime" then
        init = require("src/enemies/slime")
    end

    enemy = init(enemy, x, y, args)

    -- An enemy notices the player when it hears them (very close) or sees them:
    -- no wall in between, within `aggroRange` all around it, or (without an
    -- aggroRange) up to 54 px in the direction it is facing.
    function enemy:lookForPlayer()
        if self.physics == nil then return false end
        local ex = self.physics:getX()
        local ey = self.physics:getY()
        local d = distanceBetween(ex, ey, player:getX(), player:getY())

        -- the 'listening' threshold
        if d < 30 then
            return true
        end

        local range = self.aggroRange or 54
        if d > range + 8 then return false end

        -- Only look at player if they are in the direction enemy is facing
        if not self.aggroRange and self.state >= 1 and self.state < 2 then
            if self.scaleX == 1 and ex > player:getX() then return false end
            if self.scaleX == -1 and ex < player:getX() then return false end
        end

        local toPlayerVec = getPlayerToSelfVector(ex, ey):rotateInplace(math.pi)

        debug.lineX1 = ex
        debug.lineY1 = ey

        -- line of queries going towards the player
        for i=1,math.floor(range / 3) do
            local qRad = 3
            local qx = ex + toPlayerVec.x * i * qRad
            local qy = ey + toPlayerVec.y * i * qRad

            debug.lineX2 = qx
            debug.lineY2 = qy

            local hitPlayer = world:queryCircleArea(qx, qy, qRad, {'Player'})
            if #hitPlayer > 0 then
                return true
            end

            local obstacles = world:queryCircleArea(qx, qy, qRad, {'Wall'})
            if #obstacles > 0 then
                return false
            end
        end

        return false
    end

    -- Used to make enemies move within a circular area
    function enemy:wanderUpdate(dt)
        if self.state < 1 or self.state >= 2 or self.dizzyTimer > 0 then return end
        if self.wanderTimer > 0 then self.wanderTimer = self.wanderTimer - dt end
        if self.wanderBufferTimer > 0 then self.wanderBufferTimer = self.wanderBufferTimer - dt end
        if self.wanderTimer < 0 then
            self.state = 1.1
            self.wanderTimer = 0

            local ex = self.physics:getX()
            local ey = self.physics:getY()

            if ex < self.startX and ey < self.startY then
                self.wanderDir = vector(0, 1)
            elseif ex > self.startX and ey < self.startY then
                self.wanderDir = vector(-1, 0)
            elseif ex < self.startX and ey > self.startY then
                self.wanderDir = vector(1, 0)
            else
                self.wanderDir = vector(0, -1)
            end

            self.wanderBufferTimer = 0.2
            self.wanderDir:rotateInplace(math.pi/-2 * math.random())
        end

        if self.state == 1.1 and self.physics then
            self.physics:setX(self.physics:getX() + self.wanderDir.x * self.wanderSpeed * dt)
            self.physics:setY(self.physics:getY() + self.wanderDir.y * self.wanderSpeed * dt)

            if distanceBetween(self.physics:getX(), self.physics:getY(), self.startX, self.startY) > self.wanderRadius and self.wanderBufferTimer <= 0 then
                self.state = 1
                self.wanderTimer = 1 + math.random(0.1, 0.8)
            end
        end
        --self:lookForPlayer()
    end

    function enemy:setScaleX()
        local px, py = player:getPosition()
        local ex, ey = self.physics:getPosition()

        if self.state >= 99 then
            if px < ex then
                self.scaleX = -1
            else
                self.scaleX = 1
            end
        elseif self.state >= 1 and self.state < 2 then
            if self.wanderDir.x < 0 then
                self.scaleX = -1
            else
                self.scaleX = 1
            end
        end
    end

    function enemy:moveLogic(dt, stiff)
        if self.stunTimer > 0 then
            self.stunTimer = self.stunTimer - dt
        end
        if self.stunTimer < 0 then
            self.stunTimer = 0
            self.physics:setLinearVelocity(0, 0)
        end

        if self.dizzyTimer > 0 then
            self.dizzyTimer = self.dizzyTimer - dt
        end
        if self.dizzyTimer < 0 then
            self.dizzyTimer = 0
        end

        if self.stunTimer == 0 and self.dizzyTimer == 0 then
            self.anim:update(dt * self.moving)
            local px, py = player:getPosition()
            local ex, ey = self.physics:getPosition()

            if self.state < 99 then
                if self:lookForPlayer() then
                    self.state = 99 -- alerted state
                    self.animTimer = 0.5
                end
            end

            if self.state >= 100 then
                self.dir = vector(px - ex, py - ey):normalized() * self.magnitude

                if self.chase then
                    if stiff then -- Stiff (grounded) movement
                        self.physics:setX(self.physics:getX() + self.dir.x * dt)
                        self.physics:setY(self.physics:getY() + self.dir.y * dt)
                    else -- Floaty movement
                        if distanceBetween(0, 0, self.physics:getLinearVelocity()) < self.maxSpeed then
                            self.physics:applyForce(self.dir:unpack())
                        end
                    end
                elseif self.aggro then
                    self:aggro(dt)
                end
            end

            if self.health <= 0 then
                self.dead = true
                --self:die()
                local ex, ey = self.physics:getPosition()
                particleEvent("death", ex, ey)
                dj.play(sounds.enemies.die, "static", "effect")
            end
        else

        end
    end

    -- This update function is the same for all enemies, regardless of type
    function enemy:genericUpdate(dt)
        if self.flashTimer > 0 then
            self.flashTimer = self.flashTimer - dt
            if self.flashTimer < 0 then
                self.flashTimer = 0
            end
        end

        if self.burningTimer > 0 then
            self.burningTimer = self.burningTimer - dt
            if self.burningTimer < 0 then
                self.burningCounter = self.burningCounter - 1
                if self.burningCounter > 0 then
                    -- trigger damage TODO
                    self.burningTimer = 1
                else
                    self.burningTimer = 0
                end
            end
        end

        if self.emberTimer > 0 then
            self.emberTimer = self.emberTimer - dt
            if self.emberTimer < 0 then
                if self.burningCounter > 0 then
                    effects:spawn("enemyEmber", self.physics:getX(), self.physics:getY(), {scale = 0.6})
                    effects:spawn("enemyEmber", self.physics:getX(), self.physics:getY(), {scale = 0.6})
                    self.emberTimer = 0.033
                else
                    self.emberTimer = 0
                end
            end
        end

        if self.animTimer > 0 then
            self.animTimer = self.animTimer - dt
            if self.animTimer < 0 then
                if self.state == 99 then self.state = 100 end -- Begin attacking
                self.animTimer = 0
            end
        end

        if self.hookVec and self.dizzyTimer > 0 and grapple.state == -1 then
            self.physics:setLinearVelocity(0, 0)
            self.physics:setX( self.physics:getX() + (self.hookVec.x * grapple.speed * -1 * dt) )
            self.physics:setY( self.physics:getY() + (self.hookVec.y * grapple.speed * -1 * dt) )
        end

        self:wanderUpdate(dt)
    end

    function enemy:hit(damage, dir, stun, dizziness)
        self.health = self.health - damage
        self.stunTimer = stun
        local mag = 200
        if self.health <= 0 then
            self.stunTimer = stun*2.25
            mag = 260
        end
        shake:start(0.1, 1, 0.02)
        self.physics:applyLinearImpulse((dir:normalized()*mag):unpack())
        self.flashTimer = 0.175
        if damage == 0 then self.flashTimer = 0 end
        self.dizzyTimer = dizziness or 0
        globalStun = 0.05
        self.state = 100

        if damage > 0 then
            for i=1,14 do
                effects:spawn("damage", self.physics:getX(), self.physics:getY(), {dir = dir})
            end
        else
            
        end
        local range = math.random()/4
        dj.play(sounds.enemies.hurt, "static", "effect", 1, 1+range)
    end

    function enemy:burn()
        self.burningTimer = 1
        self.burningCounter = 5
        self.emberTimer = 0.1
    end

    function enemy:debugRadius()
        if distanceBetween(player:getX(), player:getY(), self.physics:getX(), self.physics:getY()) < self.debugRad then
            d1 = "Detected"
        else
            d1 = "Not detected"
        end
    end

    function enemy:drawDebugRadius()
        love.graphics.setColor(0, 0, 1, 0.25)
        love.graphics.circle('fill', self.physics:getX(), self.physics:getY(), self.debugRad)
    end

    table.insert(enemies, enemy)
    return enemy

end

function enemies:update(dt)

    -- Calls update functions on all enemies
    for i,e in ipairs(self) do
        e:update(dt)
        e:genericUpdate(dt)
    end
  
    enemies:destroyDead()
  
end

-- Draw all enemies
local function drawEnemy(e)
    if e.flashTimer > 0 then love.graphics.setShader(shaders.whiteout) end
    e:draw()
    love.graphics.setShader()
end

-- each enemy, for the depth-sorted world (src/draw.lua): behind a tree or in
-- front of it, by where it stands
function enemies:collect(items)
    for _, e in ipairs(self) do
        if e.physics then
            table.insert(items, { y = e.physics:getY() + 4, draw = drawEnemy, arg = e })
        end
    end
end

-- the flames on whoever a Fireball set alight, over everything
function enemies:drawBurning()
    local burning = {}
    for _, e in ipairs(self) do
        if e.burningCounter > 0 and not e.dead and e.physics then table.insert(burning, e) end
    end
    -- whoever a Fireball set alight burns until the fire goes out
    if #burning > 0 then
        pixelfx.world(function()
            for _, e in ipairs(burning) do
                effects:drawFlame(e.physics:getX(), e.physics:getY() + 5, 0.5, 0.9)
            end
        end)
    end
end

-- removes defeated enemies; they stay gone when the map is entered again
function enemies:destroyDead()
    local i = #enemies
    while i > 0 do
        if enemies[i].dead then
            if enemies[i].key then
                data.defeated[enemies[i].key] = true
            end
            if enemies[i].physics then
                local ex, ey = enemies[i].physics:getPosition()
                mobLoot:drop(enemies[i], ex, ey)
            end
            if enemies[i].spawner then
                enemies[i].spawner.alive = math.max(0, enemies[i].spawner.alive - 1)
            end
            if enemies[i].physics then
                enemies[i].physics:destroy()
            end
            table.remove(enemies, i)
        end
        i = i - 1
    end
end

function spawnEnemyLoot(x, y)
    -- TODO: this code is not good, make a proper loot-rolling system
    if math.random() > 0.5 then
        --return -- 50/50 no loot
    end
    local lootType = "arrow"
    local randCheck = math.random()
    if player.health < data.maxHealth then
        if randCheck < 0.33 then
            lootType = "heart"
        elseif randCheck < 0.66 then
            lootType = "bomb"
        end
    else
        if randCheck < 0.5 then
            lootType = "bomb"
        end
    end
    -- disable enemy spawn loot for now
    --spawnLoot(x, y, lootType, true)
end
