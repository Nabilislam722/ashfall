-- Roaming bosses. A map's "Boss" layer can hold a "demonLord" rectangle (the
-- Forest Clearing's does): the Demon General (src/enemies/demonLord.lua) strolls
-- about inside it, minding his own business, until the hero comes close or
-- strikes him. Then he turns on them and fights to the end, with his health
-- bar at the top of the screen. Beaten, he stays beaten (data.defeated.demonLord)
-- and leaves the hero a heart and a purse of gold. Leaving the map, or falling
-- to him, puts him back where he was: unhurt, and calm again.

roamingBoss = {}
roamingBoss.active = false
roamingBoss.redFlash = 0

local KEY = "demonLord"
local REWARD_GOLD = 150
local FIGHT_ZOOM = 0.8   -- the camera pulls back at least this far while he fights

function roamingBoss:clear()
    if self.lord then self.lord:destroy() end
    self.lord = nil
    self.active = false
    self.fighting = false
    self.displayHealth = nil
    if self.prevZoom then
        setZoomLevel(self.prevZoom)
        self.prevZoom = nil
    end
end

function roamingBoss:onMapLoaded(map, mapName)
    self:clear()
    local layer = map.layers["Boss"]
    if not layer or not layer.objects or data.defeated[KEY] then return end
    for _, obj in ipairs(layer.objects) do
        if obj.name == KEY then
            local roam = { x = obj.x, y = obj.y, w = obj.width, h = obj.height }
            local arena = { x = 0, y = 0, w = map.width * map.tilewidth, h = map.height * map.tileheight }
            self.lord = spawnDemonLord(roam.x + roam.w / 2, roam.y + roam.h / 2, roam, arena)
            self.active = true
        end
    end
end

-- he turned on the hero
function roamingBoss:onAggro(lord)
    self.fighting = true
    self.displayHealth = lord.health
    if zoomTarget > FIGHT_ZOOM then
        self.prevZoom = zoomTarget
        setZoomLevel(FIGHT_ZOOM)
    end
    showToast("The Demon General turns on you! Swing into his white glints, dodge the red.", 3.5)
end

-- at half health
function roamingBoss:onEnrage()
    self.redFlash = 1
    showToast("The Demon General's hellfire awakens!", 2.5)
end

-- once he has crumbled away
function roamingBoss:onDefeated(lord)
    self.fighting = false
    self.lord = nil
    self.active = false
    cam.bias = nil
    data.defeated[KEY] = true
    data.maxHealth = data.maxHealth + 1
    player.health = data.maxHealth
    data.money = data.money + REWARD_GOLD
    data.goldEarned = data.goldEarned + REWARD_GOLD
    if self.prevZoom then
        setZoomLevel(self.prevZoom)
        self.prevZoom = nil
    end
    dj.play(sounds.items.chest, "static", "effect", 1, 0.9)
    floatTexts:spawn(player:getX(), player:getY() - 20, "+1 heart   +" .. REWARD_GOLD .. " gold", {1, 0.85, 0.35}, { big = true, life = 2.2 })
    showToast("The Demon General is defeated!", 4)
end

function roamingBoss:update(dt)
    if self.redFlash > 0 then self.redFlash = math.max(0, self.redFlash - dt * 1.5) end
    local lord = self.lord
    if not lord then return end
    lord:update(dt)
    if not self.lord then return end -- he fell this frame
    if self.fighting then
        -- keep him in frame while he fights
        cam.bias = cam.bias or {}
        cam.bias.x, cam.bias.y, cam.bias.weight = lord.x, lord.y - 24, 0.3
        self.displayHealth = (self.displayHealth or lord.health) + (lord.health - (self.displayHealth or lord.health)) * math.min(1, dt * 6)
    end
end

----------------------------------------------------------------------- draw

function roamingBoss:drawGround()
    if self.lord then self.lord:drawGround() end
end

-- him, sorted with everyone else
function roamingBoss:collect(items)
    local lord = self.lord
    if not lord then return end
    local _, fy = lord:feet()
    table.insert(items, { y = fy + 2, draw = function() lord:draw() end })
end

function roamingBoss:drawAir()
    if self.lord then self.lord:drawAir() end
    setWhite()
end

-- his fire glows through the dark of night (called after it is drawn)
function roamingBoss:drawEmissive()
    if not self.lord then return end
    cam:attach()
    self.lord:drawEmissive()
    cam:detach()
end

-- his light, and his fire's (lighting:sources)
function roamingBoss:addLights(list)
    if self.lord then self.lord:addLights(list) end
end

function roamingBoss:drawHUD()
    if self.redFlash > 0 then
        love.graphics.setColor(1, 0.1, 0.1, 0.35 * self.redFlash)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
    local lord = self.lord
    if not lord or not self.fighting then
        setWhite()
        return
    end

    local w = love.graphics.getWidth()
    local barW, barH = 140 * scale, 4 * scale
    local x, y = (w - barW) / 2, 9 * scale
    local border = math.max(2, math.floor(scale * 0.6))
    love.graphics.setFont(fonts.small)
    local title = lord.enraged and "DEMON GENERAL  -  HELLFIRE" or "DEMON GENERAL"
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.printf(title, x + scale * 0.4, y - fonts.small:getHeight() - scale * 0.6, barW, "center")
    if lord.enraged then
        love.graphics.setColor(1, 0.35 + 0.25 * math.sin(love.timer.getTime() * 10), 0.3, 1)
    else
        love.graphics.setColor(1, 0.6, 0.55, 1)
    end
    love.graphics.printf(title, x, y - fonts.small:getHeight() - scale, barW, "center")

    love.graphics.setColor(0.05, 0.04, 0.06, 0.9)
    love.graphics.rectangle("fill", x - border, y - border, barW + border * 2, barH + border * 2, scale * 0.5, scale * 0.5)
    local ratio = math.max(0, (self.displayHealth or lord.health) / lord.maxHealth)
    local trueRatio = math.max(0, lord.health / lord.maxHealth)
    love.graphics.setColor(1, 0.9, 0.7, 0.8)
    love.graphics.rectangle("fill", x, y, barW * math.max(ratio, trueRatio), barH)
    love.graphics.setColor(lord.enraged and 1 or 0.78, lord.enraged and 0.22 or 0.1, 0.16, 1)
    love.graphics.rectangle("fill", x, y, barW * math.min(ratio, trueRatio), barH)
    -- half health: where the hellfire wakes
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.rectangle("fill", x + barW * 0.5 - 1, y - border, 2, barH + border * 2)
    setWhite()
end
