-- Slimes of the Whispering Woods. They wobble about until they notice the hero
-- (all around them, not only ahead), then hop after them and, close up, attack:
--   form 1, blue: the weakest; squirts a spray of water a short way ahead
--   form 2, yellow: crackles for a moment, then bursts with lightning all
--     around it (step out of the ring, or dodge through it)
--   form 3, red: the toughest; rears up and lunges with its jaws
-- A hit interrupts the attack it was winding up. Touching any of them stings,
-- as with every monster. Beaten, they melt into a puddle (effect "slimeDeath")
-- and leave a blob of gel for the guild (src/items/mobLoot.lua).

local FORMS = {
    { health = 3, speed = 34, range = 24, windup = 0.35, damage = 0.5, cooldown = 1.1 },
    { health = 4, speed = 26, range = 30, windup = 0.6, damage = 0.5, cooldown = 1.6, burst = 26 },
    { health = 6, speed = 30, range = 44, windup = 0.45, damage = 1, cooldown = 1.4, lunge = 190 },
}
local STRIKE_TIME = 0.42    -- the attack's follow-through (the second half of its frames)
local LUNGE_TIME = 0.2
local ROWS = { down = 1, up = 2, left = 3, right = 4 }

local quads = {} -- [sheet][row][frame]

local function quad(sheet, row, frame)
    local bySheet = quads[sheet]
    if not bySheet then
        bySheet = {}
        quads[sheet] = bySheet
    end
    local byRow = bySheet[row]
    if not byRow then
        byRow = {}
        for f = 1, sheet:getWidth() / 64 do
            byRow[f] = love.graphics.newQuad((f - 1) * 64, (row - 1) * 64, 64, 64, sheet:getDimensions())
        end
        bySheet[row] = byRow
    end
    return byRow[frame], #byRow
end

local function facingOf(dx, dy)
    if math.abs(dx) > math.abs(dy) then return dx < 0 and "left" or "right" end
    return dy < 0 and "up" or "down"
end

local function slimeInit(enemy, x, y, args)
    enemy.physics = world:newBSGRectangleCollider(x - 6, y - 4, 12, 8, 3)
    enemy.physics:setCollisionClass('Enemy')
    enemy.physics:setFixedRotation(true)
    enemy.physics:setMass(1)
    enemy.physics:setLinearDamping(6)
    enemy.physics.parent = enemy

    enemy.form = math.max(1, math.min(3, tonumber(args and args.form) or 1))
    local f = FORMS[enemy.form]
    enemy.sheets = sprites.enemies.slimes[enemy.form]
    enemy.health = f.health
    enemy.chase = false       -- it moves itself (enemy:aggro)
    enemy.magnitude = f.speed -- (moveLogic works out a chase direction from this all the same)
    enemy.aggroRange = 70     -- and senses the hero all around it
    enemy.scaleX = 1
    enemy.facing = "down"
    enemy.mode = "hop"        -- hop, windup, strike
    enemy.modeTime = 0
    enemy.cooldown = 0.4
    enemy.animTime = math.random()
    enemy.hurtTime = 0
    enemy.anim = { update = function() end } -- (moveLogic expects one; the frames are picked in draw)

    -- close in, then attack
    function enemy:aggro(dt)
        local ex, ey = self.physics:getPosition()
        local px, py = player:getPosition()
        local dx, dy = px - ex, py - ey
        local d = math.max(0.001, math.sqrt(dx * dx + dy * dy))
        if self.mode == "hop" then
            self.facing = facingOf(dx, dy)
            self.cooldown = self.cooldown - dt
            if d < f.range and self.cooldown <= 0 then
                self.mode, self.modeTime = "windup", 0
                self.physics:setLinearVelocity(0, 0)
                self.aimX, self.aimY = dx / d, dy / d
                if self.form == 2 then dj.play("sounds/items/zap.wav", "static", "effect", 0.5, 1.3) end
            else
                -- slimes move in little surges, quicker as they squash and stretch
                local surge = 0.6 + 0.8 * math.abs(math.sin(self.animTime * 7))
                self.physics:setLinearVelocity(dx / d * f.speed * surge, dy / d * f.speed * surge)
            end
        elseif self.mode == "windup" then
            self.modeTime = self.modeTime + dt
            self.physics:setLinearVelocity(0, 0)
            if self.modeTime >= f.windup then self:strike() end
        elseif self.mode == "strike" then
            self.modeTime = self.modeTime + dt
            if self.form == 3 and self.modeTime < LUNGE_TIME then
                self.physics:setLinearVelocity(self.aimX * f.lunge, self.aimY * f.lunge)
                if not self.bit and d < 14 then
                    self.bit = true
                    player:hurt(f.damage, ex, ey)
                end
            else
                self.physics:setLinearVelocity(0, 0)
            end
            if self.modeTime >= STRIKE_TIME then
                self.mode = "hop"
                self.cooldown = f.cooldown
            end
        end
    end

    function enemy:strike()
        self.mode, self.modeTime = "strike", 0
        local ex, ey = self.physics:getPosition()
        local px, py = player:getPosition()
        if self.form == 1 then
            -- a spray of water just ahead
            dj.play(sounds.enemies.projectile, "static", "effect", 0.6, 1.5)
            if distanceBetween(ex + self.aimX * 14, ey + self.aimY * 14, px, py) < 13 then
                player:hurt(f.damage, ex, ey)
            end
        elseif self.form == 2 then
            -- lightning all around
            dj.play("sounds/items/zap.wav", "static", "effect", 0.9, 0.9)
            shake:start(0.12, 1.5, 0.02)
            if distanceBetween(ex, ey, px, py) < f.burst then
                player:hurt(f.damage, ex, ey)
            end
        else
            -- the lunge (enemy:aggro carries it)
            self.bit = false
            dj.play(sounds.player.roll, "static", "effect", 0.9, 0.7)
        end
    end

    function enemy:update(dt)
        self.animTime = self.animTime + dt
        if self.stunTimer > 0 then
            -- hit: the attack it was winding up is lost
            if self.mode ~= "hop" then self.mode, self.cooldown = "hop", f.cooldown * 0.5 end
            self.hurtTime = self.hurtTime + dt
        else
            self.hurtTime = 0
        end
        if self.state == 1.1 then
            self.facing = facingOf(self.wanderDir.x, self.wanderDir.y)
        end
        self:moveLogic(dt)
        if self.dead and not self.melted then
            self.melted = true
            local ex, ey = self.physics:getPosition()
            effects:spawn("slimeDeath", ex, ey, { sheet = self.sheets.death, row = ROWS[self.facing] })
        end
    end

    -- which sheet and frame to show now
    function enemy:frame()
        local row = ROWS[self.facing]
        if self.stunTimer > 0 then
            local q, n = quad(self.sheets.hurt, row, 1)
            return self.sheets.hurt, quad(self.sheets.hurt, row, math.min(n, 1 + math.floor(self.hurtTime / 0.06)))
        end
        if self.mode == "windup" or self.mode == "strike" then
            -- the first 4 frames wind up, the rest are the attack itself
            local frame
            if self.mode == "windup" then
                frame = 1 + math.min(3, math.floor(self.modeTime / f.windup * 4))
            else
                frame = 5 + math.min(5, math.floor(self.modeTime / STRIKE_TIME * 6))
            end
            return self.sheets.attack, quad(self.sheets.attack, row, frame)
        end
        local moving = self.state == 1.1 or (self.state >= 100 and self.mode == "hop")
        local sheet = moving and self.sheets.walk or self.sheets.idle
        local _, n = quad(sheet, row, 1)
        return sheet, quad(sheet, row, 1 + math.floor(self.animTime / (moving and 0.09 or 0.13)) % n)
    end

    function enemy:draw()
        local ex, ey = self.physics:getPosition()
        local sheet, q = self:frame()
        if self.flashTimer > 0 then
            love.graphics.setColor(1, 0.75, 0.75, 1)
        else
            setWhite()
        end
        love.graphics.draw(sheet, q, math.floor(ex + 0.5), math.floor(ey + 0.5), 0, 1, 1, 32, 37)
        setWhite()
        if self.state == 99 then
            love.graphics.draw(sprites.enemies.alert, ex, ey - 18, nil, nil, nil, sprites.enemies.alert:getWidth() / 2, sprites.enemies.alert:getHeight() / 2)
        end
    end

    return enemy
end

return slimeInit
