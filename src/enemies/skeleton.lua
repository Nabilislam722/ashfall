-- The knife skeleton closes in, stops, raises its knife (a white glint: the hero
-- can meet it with a swing, src/utilities/combat.lua) and slashes. A clash, or a
-- hit, breaks the slash off.
local SLASH = { reach = 20, windup = 0.42, active = 0.12, recover = 0.35, cooldown = 1.1, damage = 0.5 }

local function skeletonInit(enemy, x, y, args)
    enemy.physics = world:newBSGRectangleCollider(x, y, 12, 16, 3)
    enemy.physics:setCollisionClass('Enemy')
    enemy.physics:setFixedRotation(true)
    enemy.physics:setMass(1)
    enemy.physics:setLinearDamping(2)
    enemy.physics.parent = enemy

    enemy.form = 1
    enemy.sprite = sprites.enemies.skeletonKnife

    if args and args.form ~= nil then
        enemy.form = args.form
    end

    enemy.health = 6
    enemy.magnitude = 40
    enemy.slash = nil          -- { phase = "windup" | "active" | "recover", t, dir }
    enemy.slashCooldown = 0.6
    enemy.dir = vector(0, 1)
    enemy.viewDistance = 100

    if enemy.form == 2 then -- Mage
        enemy.sprite = sprites.enemies.skeletonMage
        enemy.chase = false
        enemy.projTimer = 0

        function enemy:aggro(dt)
            self.projTimer = self.projTimer - dt
            if self.projTimer < 0 then
                if self.state == 100 then
                    self.state = 101
                    self.projTimer = 1.2
                    enemy.anim = enemy.animations.walk
                elseif self.state == 101 then
                    self.state = 100
                    self.projTimer = 0.4
                    enemy.anim = enemy.animations.staff
                    spawnProjectile('mage', self.physics:getX(), self.physics:getY())
                end
            end

            if self.state == 101 then
                self.dir = getSelfToPlayerVector(self.physics:getX(), self.physics:getY())*10 -- speed
                self.physics:setX(self.physics:getX() + self.dir.x * dt)
                self.physics:setY(self.physics:getY() + self.dir.y * dt)
            end
        end
    end

    enemy.grid = anim8.newGrid(20, 24, enemy.sprite:getWidth(), enemy.sprite:getHeight())

    enemy.animations = {}
    enemy.animations.walk = anim8.newAnimation(enemy.grid('1-2', 1), 0.4)

    if enemy.form == 2 then
        enemy.animations.staff = anim8.newAnimation(enemy.grid(3, 1), 1)
    end

    enemy.anim = enemy.animations.walk

    enemy.scaleX = 1
    if math.random() < 0.5 then enemy.scaleX = -1 end

    -- Used to control the walk animation
    -- 0: standing still
    -- 1: walking
    -- 2: running
    enemy.moving = 0

    -- close up: a telegraphed slash of the knife
    function enemy:updateSlash(dt)
        if self.slashCooldown > 0 then self.slashCooldown = self.slashCooldown - dt end
        local px, py = player:getPosition()
        local ex, ey = self.physics:getPosition()
        local toPlayer = vector(px - ex, py - ey)
        local d = toPlayer:len()
        if self.stunTimer > 0 or self.dizzyTimer > 0 or self.dead then
            if self.slash then self:endSlash() end
            return
        end
        local s = self.slash
        if not s then
            if self.state >= 100 and d < SLASH.reach and self.slashCooldown <= 0 and not isPlayerFrozen() then
                local dir = d > 0.01 and toPlayer:normalized() or vector(self.scaleX, 0)
                self.slash = { phase = "windup", t = 0, dir = dir }
                self.chase = false
                combat:glint(ex + dir.x * 8, ey - 8, "parry")
            end
            return
        end
        s.t = s.t + dt
        self.physics:setLinearVelocity(0, 0)
        if s.phase == "windup" and s.t >= SLASH.windup then
            s.phase, s.t = "active", 0
            effects:spawn("slice", ex, ey, s.dir)
            dj.play(sounds.items.sword, "static", "effect", 0.7, 0.75)
            -- the knife reaches out in front of it
            if d < SLASH.reach + 6 and (d < 0.01 or (s.dir.x * toPlayer.x + s.dir.y * toPlayer.y) / d > 0.3) then
                combat:melee(self, SLASH.damage, ex + s.dir.x * 8, ey + s.dir.y * 8)
            end
        elseif s.phase == "active" and s.t >= SLASH.active then
            s.phase, s.t = "recover", 0
        elseif s.phase == "recover" and s.t >= SLASH.recover then
            self:endSlash()
        end
    end

    function enemy:endSlash()
        self.slash = nil
        self.chase = true
        self.slashCooldown = SLASH.cooldown
    end

    -- the hero's sword meets its knife mid-slash
    function enemy:striking()
        return self.slash ~= nil and self.slash.phase == "active"
    end

    -- blade on blade: it staggers back, its slash spent
    function enemy:onClash(dir)
        self:endSlash()
        self.stunTimer = 0.45
        self.physics:applyLinearImpulse(dir.x * 120, dir.y * 120)
    end

    function enemy:update(dt)
        enemy:moveLogic(dt, true) -- Stiff movement
        if self.form == 1 then self:updateSlash(dt) end
        local px, py = player:getPosition()
        local ex, ey = self.physics:getPosition()
        
        self:setScaleX()

        if self.state == 1 or self.state == 99 then
            self.moving = 0
            if self.anim then self.anim:gotoFrame(1) end
        elseif self.state == 1.1 then
            self.moving = 1
        else
            if self.form == 2 then
                self.moving = 1
            else
                self.moving = 2
            end
        end

    end

    function enemy:draw()
        setWhite()
        local ex, ey = self.physics:getPosition()
        local shadow = sprites.enemies.shadowMed
        local shadowOff = -0.75 * self.scaleX
        love.graphics.draw(shadow, ex + shadowOff, ey+9, nil, nil, nil, shadow:getWidth()/2, shadow:getHeight()/2)
        if self.flashTimer > 0 then
            love.graphics.setColor(223/255,106/255,106/255,1)
        elseif self.slash and self.slash.phase == "windup" then
            -- the knife goes up: it pales as the slash comes
            local k = self.slash.t / SLASH.windup
            love.graphics.setColor(1, 1 - 0.15 * k, 1 - 0.35 * k, 1)
        end
        if self.dizzyTimer == 0 then
            self.anim:draw(self.sprite, ex, ey, nil, self.scaleX, 1, 10, 12)
        else
            love.graphics.draw(sprites.enemies.skeletonDead, ex - (3*self.scaleX), ey-4, nil, self.scaleX, 1, 8, 8)
        end
        setWhite()
        if self.state == 99 then
            love.graphics.draw(sprites.enemies.alert, ex, ey-14.5, nil, nil, nil, sprites.enemies.alert:getWidth()/2, sprites.enemies.alert:getHeight()/2)
        end
    end

    function enemy:die()
        local ex, ey = self.physics:getPosition()
        local args = {}
        args.scaleX = self.scaleX
        args.form = self.form
        effects:spawn("batDeath", ex, ey+3, args)
    end

    return enemy

end

return skeletonInit