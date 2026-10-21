player = world:newBSGRectangleCollider(234, 184, 12, 12, 3)
player.x = 0
player.y = 0
player.dir = "down"
player.dirX = 1
player.dirY = 1
player.prevDirX = 1
player.prevDirY = 1
player.scaleX = 1
player.speed = 90
player.animSpeed = 0.14
player.walking = false
player.animTimer = 0
player.health = 4
player.stunTimer = 0
player.damagedTimer = 0
player.damagedBool = 1
player.damagedFlashTime = 0.05
player.invincible = 0 -- timer
player.bowRecoveryTime = 0.25
player.holdSprite = sprites.items.heart
player.attackDir = vector(1, 0)
player.comboCount = 0
player.aiming = false
player.arrowOffX = 0
player.arrowOffX = 0
player.bowVec = vector(1, 0)
player.baseDamping = 12
player.dustTimer = 0
player.rollDelayTimer = 0
player.ammoMessageTimer = 0 -- cooldown for the "Out of arrows/bombs" popup
player.rotateMargin = 0.25
player.swordPower = 1.2 -- sword damage per hit, 20% above the original 1
player.swordReach = 1.43 -- size of the sword sweep: original, +10%, then +30%
player.shadowCooldown = 0 -- Shadow Step recharge timer
player.shadowInvuln = 0 -- untouchable while stepping through the shadows
player.afterimages = {} -- fading silhouettes left behind by Shadow Step (and the dodge)
player.stamina = 100 -- spent by dodging, rolling and Shadow Step; it comes back on its own
player.staminaMax = 100
player.staminaDelay = 0 -- a moment after spending it, before it starts coming back
player.dodging = false -- the Shift dodge's dash (player.state 0.5, like a roll)
player.dodgeInvuln = 0 -- untouchable while dodging
player.dodgeCooldown = 0
player.afterimageTimer = 0
player.shiftTap = nil -- Shift held: { t = when it went down, clicked = a click came meanwhile }

-- 0 = Normal gameplay
-- 0.5 = Rolling
-- 1 = Sword swing
-- 2 = Use (bomb)
-- 3 = Bow (3: bow drawn, 3.1: recover)
-- 4 = grapple (4: armed, 4.1: launching, 4.2: moving)
-- 10 = Damage stun
-- 11 = Hold item
-- 12 = Transition
player.state = -1

player:setCollisionClass("Player")
player:setFixedRotation(true)
player:setLinearDamping(player.baseDamping)

player.grid = anim8.newGrid(19, 21, sprites.playerSheet:getWidth(), sprites.playerSheet:getHeight())

player.animations = {}
player.animations.downRight = anim8.newAnimation(player.grid('1-2', 1), player.animSpeed)
player.animations.downLeft = anim8.newAnimation(player.grid('1-2', 1), player.animSpeed)
player.animations.upRight = anim8.newAnimation(player.grid('1-2', 2), player.animSpeed)
player.animations.upLeft = anim8.newAnimation(player.grid('1-2', 2), player.animSpeed)
player.animations.swordDownRight = anim8.newAnimation(player.grid('1-2', 1), player.animSpeed)
player.animations.swordDownLeft = anim8.newAnimation(player.grid('1-2', 1), player.animSpeed)
player.animations.swordUpRight = anim8.newAnimation(player.grid('1-2', 2), player.animSpeed)
player.animations.swordUpLeft = anim8.newAnimation(player.grid('1-2', 2), player.animSpeed)
player.animations.useDownRight = anim8.newAnimation(player.grid(2, 1), player.animSpeed)
player.animations.useDownLeft = anim8.newAnimation(player.grid(2, 1), player.animSpeed)
player.animations.useUpRight = anim8.newAnimation(player.grid(2, 2), player.animSpeed)
player.animations.useUpLeft = anim8.newAnimation(player.grid(2, 2), player.animSpeed)
player.animations.hold = anim8.newAnimation(player.grid(1, 1), player.animSpeed)
player.animations.rollDown = anim8.newAnimation(player.grid('1-3', 4), 0.11)
player.animations.rollUp = anim8.newAnimation(player.grid('1-3', 5), 0.11)
player.animations.stopDown = anim8.newAnimation(player.grid('1-3', 6), 0.22, function() player.anim = player.animations.idleDown end)
player.animations.stopUp = anim8.newAnimation(player.grid('1-3', 7), 0.22, function() player.anim = player.animations.idleUp end)
player.animations.idleDown = anim8.newAnimation(player.grid('1-4', 8), {1.2, 0.1, 2.4, 0.1})
player.animations.idleUp = anim8.newAnimation(player.grid('1-2', 9), 0.22)

player.anim = player.animations.idleDown

player.buffer = {} -- input buffer

local STAMINA_REGEN = 45  -- stamina back per second...
local STAMINA_DELAY = 0.5 -- ...from this long after it was last spent
local DODGE_STAMINA, ROLL_STAMINA, SHADOW_STAMINA = 22, 14, 30

-- spends stamina on a move; without enough, the move doesn't happen
function player:useStamina(cost)
    if player.stamina < cost then
        player:outOfAmmo("Too tired!")
        hudFlashStamina()
        return false
    end
    player.stamina = player.stamina - cost
    player.staminaDelay = STAMINA_DELAY
    return true
end

function isPlayerFrozen()
    return dialogue.active or shop.active or hemiExchange.active or manaWell.active or topMenu.open
        or cutscene.active or respawn.pending
end

function player:update(dt)

    if pause.active then player.anim:update(dt) end
    if player.state == -1 or gamestate == 0 then return end

    if player.stunTimer > 0 then
        player.stunTimer = player.stunTimer - dt
    end
    if player.stunTimer < 0 then
        player.stunTimer = 0
        if player.state == 10 then
            player.state = 0
            player:setLinearVelocity(0, 0)
        end
    end
    
    if player.damagedTimer > 0 then
        player.damagedTimer = player.damagedTimer - dt
        player.damagedFlashTime = player.damagedFlashTime - dt
        if player.damagedFlashTime < 0 then
            player.damagedFlashTime = 0.05
            player.damagedBool = player.damagedBool * -1
        end
    end
    if player.damagedTimer < 0 then
        player.damagedTimer = 0
        --world:collisionClear()
        world:collisionEventsClear()
    end

    if player.rollDelayTimer > 0 then
        player.rollDelayTimer = player.rollDelayTimer - dt
    end

    if player.ammoMessageTimer > 0 then
        player.ammoMessageTimer = player.ammoMessageTimer - dt
    end

    if player.shadowCooldown > 0 then
        player.shadowCooldown = player.shadowCooldown - dt
    end
    if player.shadowInvuln > 0 then
        player.shadowInvuln = player.shadowInvuln - dt
    end
    if player.dodgeInvuln > 0 then player.dodgeInvuln = player.dodgeInvuln - dt end
    if player.dodgeCooldown > 0 then player.dodgeCooldown = player.dodgeCooldown - dt end
    if player.staminaDelay > 0 then
        player.staminaDelay = player.staminaDelay - dt
    else
        player.stamina = math.min(player.staminaMax, player.stamina + STAMINA_REGEN * dt)
    end
    for i = #player.afterimages, 1, -1 do
        local image = player.afterimages[i]
        image.life = image.life - dt
        if image.life <= 0 then table.remove(player.afterimages, i) end
    end

    -- talking, trading, cutscenes and getting knocked out all hold the player still
    if isPlayerFrozen() and player.state ~= 12 then
        player:setLinearVelocity(0, 0)
        player.aiming = false
        if player.walking then
            player.walking = false
            player:justStop()
        end
        player.anim:update(dt)
        return
    end

    if player.state == 0 then

        player:setLinearDamping(player.baseDamping)

        player.prevDirX = player.dirX
        player.prevDirY = player.dirY
    
        local dirX = 0
        local dirY = 0

        if pause.active then return end

        if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
            dirX = 1
            player.dirX = 1
        end

        if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
            dirX = -1
            player.dirX = -1
        end

        if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
            dirY = 1
            player.dirY = 1
        end

        if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
            dirY = -1
            player.dirY = -1
        end

        if dirY == 0 and dirX ~= 0 then
            player.dirY = 1
        end

        if data.item['left'] == "bow" then
            if love.mouse.isDown(1) then
                player.aiming = true
            elseif player.aiming then
                player:useBow()
                player:setDirFromVector(player.bowVec)
                return
            end
        end
        if data.item['right'] == "bow" then
            if love.mouse.isDown(2) then
                player.aiming = true
            elseif player.aiming then
                player:useBow()
                player:setDirFromVector(player.bowVec)
                return
            end
        end

        if player.aiming then
            player:setDirFromVector(player.bowVec)
        end

        if player.walking then
            if player.dirX == 1 then
                if player.dirY == 1 then
                    player.anim = player.animations.downRight
                else
                    player.anim = player.animations.upRight
                end
            else
                if player.dirY == 1 then
                    player.anim = player.animations.downLeft
                else
                    player.anim = player.animations.upLeft
                end
            end
        end

        local speed = (staff.channeling or fireballs:charging()) and player.speed * 0.55 or player.speed
        local vec = vector(dirX, dirY):normalized() * speed
        if vec.x ~= 0 or vec.y ~= 0 then
            player:setLinearVelocity(vec.x, vec.y)
        end

        if player.walking then
            player.dustTimer = player.dustTimer - dt
            if player.dustTimer < 0 then
                player.dustTimer = 0.22
                effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = vec:normalized()})
            end
        else
            player.dustTimer = 0
        end

        if dirX == 0 and dirY == 0 then
            if player.walking then
                player.walking = false
                player:justStop()
            elseif player.aiming then
                local mvec = toMouseVector(player:getX(), player:getY())
                --if mvec.y < 0 then player.dirY = -1 end
                player:setDirFromVector(player.bowVec)
                player:justIdle()
            end
            --if player.aiming then player.anim:gotoFrame(1) end
        else
            player.walking = true
        end

        player.anim:update(dt)

        if not godMode then
            player:checkDamage()
        end
        player:checkTransition()

        if data.keys and data.keys > 0 then
            if player:enter('Wall') then
                local w = player:getEnterCollisionData('Wall')
                if w.collider.type == "lockedDoor" then
                    w.collider.dead = true
                end
            end
        end

        if player.animTimer > 0 then
            player.animTimer = player.animTimer - dt
            if player.animTimer < 0 then
                player.aiming = false
                player.animTimer = 0
            end
        end

    elseif player.state == 0.5 then

        player:checkTransition()
        player.anim:update(dt)

        if player.dodging then
            -- the dodge leaves a trail of pale afterimages
            player.afterimageTimer = player.afterimageTimer - dt
            if player.afterimageTimer <= 0 then
                player.afterimageTimer = 0.03
                table.insert(player.afterimages, { x = player:getX(), y = player:getY(), dirX = player.dirX, life = 0.2, maxLife = 0.2, color = { 0.75, 0.9, 1 } })
            end
        end

        player.animTimer = player.animTimer - dt
        if player.animTimer < 0 then
            player.state = 0
            player.animTimer = 0
            if player.dodging then
                player.dodging = false
            else
                player.rollDelayTimer = 0.3
            end
        end

    elseif player.state >= 1 and player.state < 2 then

        player.animTimer = player.animTimer - dt
        player:checkDamage()

        if player.state == 1 then
            player:setLinearVelocity((player.attackDir*90):unpack())
        elseif player.state == 1.1 then
            player:setLinearVelocity(0, 0)
        end

        if player.animTimer < 0 then
            if player.state == 1 then
                player.state = 1.1
                player.anim:gotoFrame(2)
                -- animTimer for finished sword swing stance
                player.animTimer = 0.25
                effects:spawn("slice", player:getX(), player:getY()+1, player.attackDir)
                local slice = effects[#effects]
                slice.scaleX = slice.scaleX * player.swordReach
                slice.scaleY = slice.scaleY * player.swordReach
                player:swordDamage()
            elseif player.state == 1.1 then
                player.state = 0
                player:resetAnimation(player.dir)
            end
        end

    elseif player.state == 2 or player.state == 3.1 then
        player:checkDamage()
        if player.state == 2 then
            --player:setLinearVelocity(0, 0)
        end
        player.animTimer = player.animTimer - dt

        if player.animTimer < 0 then
            player.state = 0
            player:resetAnimation(player.dir)
            player.aiming = false
        end
    
    elseif player.state == 3 then

        -- while drawing the bow back, always 'use' the item
        player:useItem(player.bowRecoveryTime)
    
    elseif player.state == 4 or player.state == 4.1 then

        -- while arming the grapple, always 'use' the item
        -- player:useItem(1)

        if player.state == 4.1 and grapple.state == -1 then
            if distanceBetween(player:getX(), player:getY(), grapple.x, grapple.y) < 12 then
                grapple.state = 0
                player.state = 0
                player:resetAnimation(player.dir)
            end
        end

    elseif player.state == 4.2 then

        player:setX( player:getX() + (grapple.dir.x * grapple.speed * dt) )
        player:setY( player:getY() + (grapple.dir.y * grapple.speed * dt) )

    elseif player.state == 11 then -- got an item

        player.animTimer = player.animTimer - dt

        if player.animTimer < 0 then
            player.state = 0
            player:resetAnimation(player.dir)
        end
    
    elseif player.state == 11.1 then -- got an item (delay)

        player.animTimer = player.animTimer - dt

        if player.animTimer < 0 then
            player:gotItem(player.holdSprite)
        end

    elseif player.state == 12 then -- transition

        player:setLinearVelocity(0, 0)
        player:resetAnimation(player.dir)

    end

    player:processBuffer(dt)

end

function player:draw()

    if player.stunTimer > 0 then
        love.graphics.setColor(223/255,106/255,106/255,1)
    elseif player.damagedTimer > 0 then
        local alpha = 0.8
        if player.damagedBool < 0 then alpha = 0.55 end
        love.graphics.setColor(1,1,1,alpha)
    else
        love.graphics.setColor(1,1,1,1)
    end

    -- Sword sprite
    local swSpr = sprites.items.sword
    local swX = 0
    local swY = 0
    local swLayer = -1
    local arrowSpr = sprites.items.arrow
    local bowSpr = sprites.items.bow1
    --local hookSpr = sprites.items.grappleArmed
    if player.aiming and (player.animTimer > 0 or data.arrowCount < 1) then bowSpr = sprites.items.bow2 end
    --if player.state == 4.1 or player.state == 4.2 then hookSpr = sprites.items.grappleHandle end

    local swordRot = 0
    if player.state == 1.1 then
        local tempVec = 0
        if player.comboCount % 2 == 0 then
            tempVec = player.attackDir:rotated(math.pi/2)
        else
            tempVec = player.attackDir:rotated(math.pi/-2)
        end
        swordRot = math.atan2(tempVec.y, tempVec.x)
        swX = tempVec.x * 12 * player.swordReach
        swY = tempVec.y * 12 * player.swordReach

        if swY > 0 then
            swLayer = 1
        end
    end

    local px = player:getX()
    local py = player:getY()+1

    local bowLayer = -1
    player.bowVec = toMouseVector(px, py)
    local bowScaleY = 1
    if player.bowVec.x < 0 then bowScaleY = -1 end
    local bowRot = math.atan2(player.bowVec.y, player.bowVec.x)
    local bowOffX = player.bowVec.x*6
    local bowOffY = player.bowVec.y*6
    local hookOffX = player.bowVec.x*6
    local hookOffY = player.bowVec.y*6
    player.arrowOffX = player.bowVec.x*6
    player.arrowOffY = player.bowVec.y*6

    if bowRot > -1 * player.rotateMargin or bowRot < (math.pi - player.rotateMargin) * -1 then
        bowLayer = 1
    end

    local r, g, b, a = love.graphics.getColor()
    for _, image in ipairs(player.afterimages) do
        local c = image.color or { 0.42, 0.24, 0.62 } -- (Shadow Step's are violet)
        love.graphics.setColor(c[1], c[2], c[3], 0.6 * image.life / image.maxLife)
        player.anim:draw(sprites.playerSheet, image.x, image.y - 2, nil, image.dirX, 1, 9.5, 10.5)
    end
    love.graphics.setColor(r, g, b, a)
    if player.shadowInvuln > 0 then
        love.graphics.setColor(0.7, 0.6, 0.9, 1)
    end

    love.graphics.draw(sprites.playerShadow, px, py+5, nil, nil, nil, sprites.playerShadow:getWidth()/2, sprites.playerShadow:getHeight()/2)

    if player.state == 1.1 and swLayer == -1 then
        love.graphics.draw(swSpr, px+swX, py+swY, swordRot, nil, nil, swSpr:getWidth()/2, swSpr:getHeight()/2)
    end

    if player.aiming and bowLayer == -1 then
        love.graphics.draw(bowSpr, px + bowOffX, py + bowOffY, bowRot, 1.15, bowScaleY, bowSpr:getWidth()/2, bowSpr:getHeight()/2)
        if data.arrowCount > 0 and player.animTimer <= 0 then love.graphics.draw(arrowSpr, px + bowOffX, py + bowOffY, bowRot, 0.85, nil, arrowSpr:getWidth()/2, arrowSpr:getHeight()/2) end
        --love.graphics.draw(hookSpr, px + hookOffX, py + hookOffY, bowRot, 1.15, nil, hookSpr:getWidth()/2, hookSpr:getHeight()/2)
    end

    if player.stunTimer > 0 then love.graphics.setShader(shaders.whiteout) end

    player.anim:draw(sprites.playerSheet, player:getX(), player:getY()-2, nil, player.dirX, 1, 9.5, 10.5)
    staff:drawHeld()

    love.graphics.setShader()

    if player.state == 1.1 and swLayer == 1 then
        love.graphics.draw(swSpr, px+swX, py+swY, swordRot, nil, nil, swSpr:getWidth()/2, swSpr:getHeight()/2)
    end

    if player.aiming and bowLayer == 1 then
        love.graphics.draw(bowSpr, px + bowOffX, py + bowOffY, bowRot, 1.15, bowScaleY, bowSpr:getWidth()/2, bowSpr:getHeight()/2)
        if data.arrowCount > 0 and player.animTimer <= 0 then love.graphics.draw(arrowSpr, px + bowOffX, py + bowOffY, bowRot, 0.85, nil, arrowSpr:getWidth()/2, arrowSpr:getHeight()/2) end
        --love.graphics.draw(hookSpr, px + hookOffX, py + hookOffY, bowRot, 1.15, nil, hookSpr:getWidth()/2, hookSpr:getHeight()/2)
    end

    if player.state == 11 then
        love.graphics.draw(player.holdSprite, player:getX(), player:getY()-18, nil, nil, nil, player.holdSprite:getWidth()/2, player.holdSprite:getHeight()/2)
    end

end

function player:checkDamage()
    if player.damagedTimer > 0 then return end

    local hitEnemies = world:queryCircleArea(player:getX(), player:getY(), 5, {'Enemy'})
    if #hitEnemies > 0 then
        local e = hitEnemies[1]
        if e.parent.dizzyTimer <= 0 and e.parent.stunTimer <= 0 and not e.parent.noContactDamage then
            player:hurt(0.5, e:getX(), e:getY(), e.parent.boss)
        end
    end

    -- to fix the overlap issue, check distance as well
    for _,e in ipairs(enemies) do
        if e.physics and distanceBetween(e.physics:getX(), e.physics:getY(), player:getX(), player:getY()) < 4 then
            player:hurt(0.5, e.physics:getX(), e.physics:getY())
        end
    end

    if player:enter('Projectile') then
        local e = player:getEnterCollisionData('Projectile')
        e.collider.dead = true
        player:hurt(0.5, e.collider:getX(), e.collider:getY())
    end
end

function player:checkTransition()
    if player:enter('Transition') then
        local t = player:getEnterCollisionData('Transition')
        if t.collider.type == "instant" then
            triggerTransition(t.collider.id, t.collider.destX, t.collider.destY)
        else
            curtain:call(t.collider.id, t.collider.destX, t.collider.destY, t.collider.type)
        end
        --triggerTransition(t.collider.id, t.collider.destX, t.collider.destY)
    end
end

-- boss: a hit from Rick or Gula staggers the hero, knocking them out of whatever
-- they were doing (a swing, a charge, aiming the bow). Anything else only hurts:
-- the weapon stays in hand
function player:hurt(damage, srcX, srcY, boss)
    if player.damagedTimer > 0 or godMode or player:untouchable() then return end
    player.damagedTimer = 2
    shake:start(0.1, 2, 0.03)
    particleEvent("playerHit", player:getX(), player:getY())
    dj.play(sounds.player.hurt, "static", "effect")
    player.health = player.health - damage
    player:setLinearVelocity((getFromToVector(srcX, srcY, player:getX(), player:getY()) * 300):unpack())
    player.stunTimer = 0.075
    if boss then
        player.state = 10 -- damaged
        player.aiming = false
    end
end

function player:swingSword()

    -- The player can only swing their sword if the player.state is 0 (regular gameplay)
    if player.state ~= 0 then
        player:addToBuffer("sword")
        return
    end

    player.comboCount = player.comboCount + 1

    player.attackDir = toMouseVector(player:getX(), player:getY())
    player:setDirFromVector(player.attackDir)

    player.state = 1

    if player.dirX == 1 then
        if player.dirY == 1 then
            player.anim = player.animations.swordDownRight
        else
            player.anim = player.animations.swordUpRight
        end
    else
        if player.dirY == 1 then
            player.anim = player.animations.swordDownLeft
        else
            player.anim = player.animations.swordUpLeft
        end
    end

    --player.anim:gotoFrame(1)
    -- animTimer for sword wind-up
    player.animTimer = 0.075

end

function player:swordDamage()
    -- Query for enemies to hit with the sword
    --local hitEnemies = world:queryCircleArea(player:getX(), player:getY(), 24, {'Enemy'})

    local px, py = player:getPosition()
    local dir = player.attackDir:normalized()
    local rightDir = dir:rotated(math.pi/2)
    local leftDir = dir:rotated(math.pi/-2)
    local r1, r2, r3 = 20 * player.swordReach, 22 * player.swordReach, 6 * player.swordReach
    local polygon = {
        px + dir.x*r1,
        py + dir.y*r1,
        px + dir:rotated(math.pi/8).x*r1,
        py + dir:rotated(math.pi/8).y*r1,
        px + dir:rotated(math.pi/4).x*r1,
        py + dir:rotated(math.pi/4).y*r1,
        px + dir:rotated(3*math.pi/8).x*r1,
        py + dir:rotated(3*math.pi/8).y*r1,
        px + rightDir.x*r2,
        py + rightDir.y*r2,
        px + rightDir.x*r2 + rightDir:rotated(math.pi/2).x*r3,
        py + rightDir.y*r2 + rightDir:rotated(math.pi/2).y*r3,
        px + leftDir.x*r2 + leftDir:rotated(math.pi/-2).x*r3,
        py + leftDir.y*r2 + leftDir:rotated(math.pi/-2).y*r3,
        px + leftDir.x*r2,
        py + leftDir.y*r2,
        px + dir:rotated(3*math.pi/-8).x*r1,
        py + dir:rotated(3*math.pi/-8).y*r1,
        px + dir:rotated(math.pi/-4).x*r1,
        py + dir:rotated(math.pi/-4).y*r1,
        px + dir:rotated(math.pi/-8).x*r1,
        py + dir:rotated(math.pi/-8).y*r1,
    }

    local range = math.random()/4
    dj.play(sounds.items.sword, "static", "effect", 1, 1+range)

    local hitEnemies = world:queryPolygonArea(polygon, {'Enemy'})
    for _,e in ipairs(hitEnemies) do
        local knockbackDir = getPlayerToSelfVector(e:getX(), e:getY())
        e.parent:hit(player.swordPower, knockbackDir, 0.1)
    end
end

function player:useItem(duration)

    if player.state ~= 3 and player.state ~= 3.1 and player.state ~= 4 and player.state ~= 4.1 then
        player.state = 2
        player:setLinearVelocity(0, 0)
    end

    --[[if player.dir == "down" then
        player.anim = player.animations.useDown
    elseif player.dir == "up" then
        player.anim = player.animations.useUp
    elseif player.dir == "right" then
        player.anim = player.animations.useRight
    elseif player.dir == "left" then
        player.anim = player.animations.useLeft
    end]]

    if player.dirX == 1 then
        if player.dirY == 1 then
            player.anim = player.animations.useDownRight
        else
            player.anim = player.animations.useUpRight
        end
    else
        if player.dirY == 1 then
            player.anim = player.animations.useDownLeft
        else
            player.anim = player.animations.useUpLeft
        end
    end

    player.anim:gotoFrame(1)
    player.animTimer = duration

end

function player:useBomb()
    if player.state ~= 0 then
        player:addToBuffer("bomb")
        return
    end

    if data.bombCount < 1 then
        player:outOfAmmo("Out of bombs!")
        return
    end

    player:useItem(0.2)
    spawnBomb()
end

-- short popup (with a cooldown) when trying to use an empty weapon
function player:outOfAmmo(text)
    if player.ammoMessageTimer > 0 then return end
    player.ammoMessageTimer = 1
    floatTexts:spawn(player:getX(), player:getY() - 14, text, {1, 0.6, 0.5}, {life = 1.1})
    dj.play(sounds.ui.click, "static", "effect", 1, 0.6)
end

function player:useBoomerang()
    if player.state ~= 0 then
        player:addToBuffer("boomerang")
        return
    end

    player:useItem(0.2)
    boomerang:throw(player.dir)
end

local FLAME_COST = 10

function player:useFire()
    if player.state ~= 0 then
        player:addToBuffer("fire")
        return
    end
    if staff.mana < FLAME_COST then
        player:outOfAmmo("Not enough mana!")
        return
    end
    staff:spend(FLAME_COST)

    player:useItem(0.35)
    player:useSet()
    local oppDir = toMouseVector(player:getX(), player:getY()):rotated(math.pi)*80
    player:setLinearVelocity(oppDir.x, oppDir.y)
    spawnFlame(player:getX()-2, player:getY()-2)
end

function player:useBow()
    if player.state ~= 0 then
        player:addToBuffer("bow")
    end

    if player.state == 0 and data.arrowCount > 0 then
        if player.aiming and player.animTimer <= 0 then
            spawnArrow(player:getX() + player.arrowOffX, player:getY()+1+player.arrowOffY)
            local oppDir = toMouseVector(player:getX() + player.arrowOffX, player:getY()+1+player.arrowOffY):rotated(math.pi)*120
            player:setLinearVelocity(oppDir.x, oppDir.y)
            player.animTimer = player.bowRecoveryTime
            player.state = 3.1
            --player.aiming = false
        end
    elseif player.state == 0 and player.aiming then
        player.aiming = false
        player:outOfAmmo("Out of arrows!")
    end
end

function player:usegrapple()
    if player.state == 0 then
        player.state = 4.1
        player.attackDir = toMouseVector(player:getX() + player.arrowOffX, player:getY()+1+player.arrowOffY)
        player:useSet()
        grapple:shoot(player.attackDir)
        player:setLinearVelocity(0, 0)
        player:setDirFromVector(player.attackDir)
    end
end

function player:resetAnimation(direction)
    --player.anim = player.animations[direction]
    if player.dirX == 1 then
        if player.dirY == 1 then
            player.anim = player.animations.idleDown
        else
            player.anim = player.animations.idleUp
        end
    else
        if player.dirY == 1 then
            player.anim = player.animations.idleDown
        else
            player.anim = player.animations.idleUp
        end
    end
    player.anim:gotoFrame(1)
end

function player:gotItem(spr, delay)
    if delay then
        player.state = 11.1
        player.animTimer = 0.5
        player.holdSprite = spr
        return
    end
    player.holdSprite = spr
    player.state = 11
    player.animTimer = 1
    player.dir = "down"
    player.anim = player.animations.hold
    player:setLinearVelocity(0, 0)
end

function player:interact()
    -- query for interactable walls
    local interactables = world:queryCircleArea(player:getX(), player:getY(), 12, {'Wall'})
    for _,i in ipairs(interactables) do
        if i.parent then
            i.parent:interact()
        end
    end
end

function player:roll()
    if player.state ~= 0 or player.rollDelayTimer > 0 then
        player:addToBuffer("roll")
        return
    end

    if pause.active then player:justIdle() return end

    local dirX = 0
    local dirY = 0

    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        dirX = 1
    end

    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        dirX = -1
    end

    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        dirY = 1
    end

    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        dirY = -1
    end

    if dirX == 0 and dirY == 0 then return end -- must have some direction to roll
    if not player:useStamina(ROLL_STAMINA) then return end

    player.state = 0.5
    player.dodging = false
    player.animTimer = 0.3

    if dirY < 0 then
        player.anim = player.animations.rollUp
    else
        player.anim = player.animations.rollDown
    end
    player.anim:gotoFrame(1)

    player:setLinearDamping(1.75)
    local dirVec = vector(dirX, dirY):normalized()*160
    player:setLinearVelocity(dirVec.x, dirVec.y)

    local range = math.random()/5
    dj.play(sounds.player.roll, "static", "effect", 1, 1+range)
    effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = dirVec, scale = 0.8})
    effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = dirVec:rotated(math.pi/8), scale = 0.6})
    effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = dirVec:rotated(math.pi/-8), scale = 0.6})
    effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = dirVec:rotated(math.pi/4), scale = 0.6})
    effects:spawn("walkDust", player:getX(), player:getY()+6, {dir = dirVec:rotated(math.pi/-4), scale = 0.6})
end

-- passing through danger: mid-dodge or mid-Shadow Step
function player:untouchable()
    return player.shadowInvuln > 0 or player.dodgeInvuln > 0
end

local DODGE_SPEED = 360
local DODGE_TIME = 0.18     -- the dash lasts this long (about 40 px)...
local DODGE_INVULN = 0.24   -- ...and nothing can touch you for a moment longer
local DODGE_COOLDOWN = 0.5

-- Shift (a tap: see love.keyreleased): a quick dash that nothing can touch,
-- monsters, their shots and Rick's and Gula's attacks alike. It goes the way
-- you are moving, or straight back from the cursor when you stand still (still
-- facing it). Walls stop it. It cuts a swing's follow-through short.
function player:dodge()
    if isPlayerFrozen() or pause.active then return end
    if player.state ~= 0 and player.state ~= 1.1 then
        player:addToBuffer("dodge")
        return
    end
    if player.dodgeCooldown > 0 then return end
    if not player:useStamina(DODGE_STAMINA) then return end

    local dirX, dirY = 0, 0
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dirX = 1 end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dirX = -1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dirY = 1 end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dirY = -1 end
    local dir
    if dirX == 0 and dirY == 0 then
        dir = toMouseVector(player:getX(), player:getY()):rotated(math.pi)
    else
        dir = vector(dirX, dirY):normalized()
        player.dirX = dirX ~= 0 and dirX or player.dirX
        player.dirY = dirY < 0 and -1 or 1
    end

    player.state = 0.5
    player.dodging = true
    player.animTimer = DODGE_TIME
    player.dodgeInvuln = DODGE_INVULN
    player.dodgeCooldown = DODGE_COOLDOWN
    player.afterimageTimer = 0
    player.anim = player.dirY < 0 and player.animations.upRight or player.animations.downRight
    player:setLinearDamping(5)
    player:setLinearVelocity(dir.x * DODGE_SPEED, dir.y * DODGE_SPEED)

    dj.play(sounds.player.roll, "static", "effect", 0.9, 1.35 + math.random() * 0.1)
    effects:spawn("walkDust", player:getX(), player:getY() + 6, {dir = dir, scale = 0.8})
    effects:spawn("walkDust", player:getX(), player:getY() + 6, {dir = dir:rotated(math.pi / 6), scale = 0.6})
    effects:spawn("walkDust", player:getX(), player:getY() + 6, {dir = dir:rotated(math.pi / -6), scale = 0.6})
end

local SHADOW_DISTANCE = 52
local SHADOW_COOLDOWN = 1.1
player.shadowCooldownMax = SHADOW_COOLDOWN
local SHADOW_INVULN = 0.35

-- Shadow Step (taught by Master Juan): blink a short distance through enemies
-- and their attacks. Stops before walls, water and villagers.
function player:shadowStep()
    if not data.skills.shadowStep or isPlayerFrozen() or pause.active then return end
    if player.state ~= 0 and player.state ~= 0.5 then return end
    if player.shadowCooldown > 0 then return end

    local dirX, dirY = 0, 0
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dirX = 1 end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dirX = -1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dirY = 1 end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dirY = -1 end
    local dir
    if dirX == 0 and dirY == 0 then
        dir = toMouseVector(player:getX(), player:getY())
    else
        dir = vector(dirX, dirY):normalized()
    end

    local sx, sy = player:getPosition()
    local tx, ty = sx, sy
    for d = 4, SHADOW_DISTANCE, 4 do
        local nx, ny = sx + dir.x * d, sy + dir.y * d
        if #world:queryCircleArea(nx, ny, 6, {'Wall', 'Ground', 'NPC'}) > 0 then break end
        tx, ty = nx, ny
    end
    if distanceBetween(sx, sy, tx, ty) < 8 then return end
    if not player:useStamina(SHADOW_STAMINA) then return end

    for i = 0, 3 do
        local t = i / 4
        table.insert(player.afterimages, {
            x = sx + (tx - sx) * t, y = sy + (ty - sy) * t,
            dirX = player.dirX, life = 0.25 + 0.08 * i, maxLife = 0.25 + 0.08 * i
        })
    end
    for _ = 1, 6 do
        effects:spawn("walkDust", sx, sy + 6, {dir = vector(math.random() - 0.5, math.random() - 0.5), scale = 0.7})
    end

    player:setPosition(tx, ty)
    player:setLinearVelocity(dir.x * 60, dir.y * 60)
    if dir.x ~= 0 then player.dirX = dir.x > 0 and 1 or -1 end
    player.shadowCooldown = SHADOW_COOLDOWN
    player.shadowInvuln = SHADOW_INVULN
    dj.play(sounds.player.roll, "static", "effect", 1, 0.55)
end

function player:shadowStepReady()
    return data.skills.shadowStep and player.shadowCooldown <= 0
end

function player:setDirFromVector(vec)
    local rad = math.atan2(vec.y, vec.x)
    if rad >= player.rotateMargin*-1 and rad < math.pi/2 then
        player.dirX = 1
        player.dirY = 1
    elseif (rad >= math.pi/2 and rad < math.pi) or (rad < (math.pi - player.rotateMargin)*-1) then
        player.dirX = -1
        player.dirY = 1
    elseif rad < 0 and rad > math.pi/-2 then
        player.dirX = 1
        player.dirY = -1
    else
        player.dirX = -1
        player.dirY = -1
    end
end

function player:useSet()
    local newDir = toMouseVector(player:getX(), player:getY())
    player:setDirFromVector(newDir)

    if player.dirX == 1 then
        if player.dirY == 1 then
            player.anim = player.animations.useDownRight
        else
            player.anim = player.animations.useUpRight
        end
    else
        if player.dirY == 1 then
            player.anim = player.animations.useDownLeft
        else
            player.anim = player.animations.useUpLeft
        end
    end
end

function player:justStop()
    if player.prevDirY < 0 then
        player.anim = player.animations.stopUp
    else
        player.anim = player.animations.stopDown
    end
    player.anim:gotoFrame(1)
end

function player:justIdle()
    if player.prevDirY < 0 then
        player.anim = player.animations.idleUp
    else
        player.anim = player.animations.idleDown
    end
    --player.anim:gotoFrame(1)
end

function player:processBuffer(dt)
    for i=#player.buffer,1,-1 do
        player.buffer[i][2] = player.buffer[i][2] - dt
    end
    for i=#player.buffer,1,-1 do
        if player.buffer[i][2] <= 0 then
            table.remove(player.buffer, i)
        end
    end

    if player.state == 0 then
        player:useBuffer()
    end
end

function player:addToBuffer(action)
    if action == "roll" and player.state == 0.5 then
        table.insert(player.buffer, {action, 0.1})
    else
        table.insert(player.buffer, {action, 0.25})
    end
end

function player:useBuffer()
    local action = nil
    if #player.buffer > 0 then
        action = player.buffer[1][1]
    end

    -- clear buffer
    for k,v in pairs(player.buffer) do player.buffer[k]=nil end

    if action == nil then return end

    if action == "sword" then
        player:swingSword()
    elseif action == "bow" then
        if not player:isBowButtonDown() then
            player.aiming = true
            player:useBow()
        end
    elseif action == "bomb" then
        player:useBomb()
    elseif action == "boomerang" then
        player:useBoomerang()
    elseif action == "fire" then
        player:useFire()
    elseif action == "roll" then
        player:roll()
    elseif action == "dodge" then
        player:dodge()
    end
end

function player:isBowButtonDown()
    if data.item['z'] == 4 then -- bow
        if love.mouse.isDown(1) then
            return true
        end
    end
    if data.item['x'] == 4 then -- bow
        if love.mouse.isDown(2) then
            return true
        end
    end
    return false
end
