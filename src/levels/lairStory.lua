-- Gula's lair, behind the north sanctum of the dungeon.
--
-- The sanctum door stays sealed until Rick has told his story at the
-- Adventurers' Guild. Inside, Gula, Demon of Gluttony (the boss who cursed
-- Rick) wakes when the hero walks into its feast hall. At 40% health Gula goes
-- berserk and all but kills the hero (hearts hit zero, but there is no dying
-- here). Then Rick walks in, cuts down any of Gula's servants still standing,
-- and as Gula gathers the same devouring spell for him: "Domain Expansion:
-- Absolute Zero." The world goes black, Gula freezes solid with the spell still
-- in its jaws, time itself stops, the hero's eyes slowly close... and they wake
-- up in Willowbrook with Rick at their side.

lairStory = {}
lairStory.active = false
lairStory.spare = false   -- while true the hero can't die (hearts stop at zero)
lairStory.redFlash = 0
lairStory.slashes = {}    -- Rick's frost cuts, fading

local DOOR = { x = 29 * 16, y = 3 * 16, w = 32, h = 32 }
local WAKE = { x = 704, y = 144 } -- where the hero wakes up in Willowbrook (the north road, by the shrine)
local BERSERK_TIME = 8            -- the most the berserk onslaught lasts

local function line(speaker, text)
    local portraits = {
        Gula = sprites.enemies.gulaPortrait,
        Rick = sprites.enemies.rickPortrait,
        Hero = sprites.npc.hero,
    }
    return { speaker = speaker, portrait = portraits[speaker], text = text }
end

local function versusCards()
    local hero = {
        image = sprites.playerSheet,
        quad = love.graphics.newQuad(0, 0, 19, 21, sprites.playerSheet:getDimensions()),
        name = "HERO",
        title = "Friend of Rick",
        color = {0.09, 0.2, 0.38},
        glow = {0.35, 0.75, 1},
    }
    local gula = {
        image = sprites.enemies.gulaPortrait,
        name = "GULA",
        title = "Demon of Gluttony",
        color = {0.3, 0.06, 0.36},
        glow = {0.85, 0.3, 1},
    }
    return hero, gula
end

function lairStory:clear()
    if self.gula then self.gula:destroy() end
    self.gula = nil
    self.active = false
    self.mapName = nil
    self.door = nil
    self.fightStarted = false
    self.fighting = false
    self.berserk = false
    self.berserkTime = 0
    self.rescue = false
    self.rick = nil
    self.arena = nil
    self.slashes = {}
    if self.prevZoom then
        setZoomLevel(self.prevZoom)
        self.prevZoom = nil
    end
end

function lairStory:doorText()
    if data.story.gulaFrozen then return "Gula sleeps beyond this door, frozen in Rick's ice... for now." end
    if data.story.guildIntro then return "The seal has cracked. Gula, Demon of Gluttony, waits beyond..." end
    return "A cursed seal holds this door. Whatever cursed Rick waits beyond..."
end

function lairStory:onMapLoaded(map, mapName)
    self:clear()
    self.mapName = mapName

    if mapName == "dungeon" then
        self.active = true
        self.door = { sealed = not data.story.guildIntro }
        if self.door.sealed then
            self.door.wall = spawnWall(DOOR.x, DOOR.y, DOOR.w, DOOR.h)
        end
        for _, sign in ipairs(signs) do
            if math.abs(sign.x - (DOOR.x + 16)) < 40 and sign.y < DOOR.y + 80 then sign.text = self:doorText() end
        end
    elseif mapName == "lair" and map.layers["Boss"] then
        self.active = true
        local sx, sy = 240, 144
        for _, obj in ipairs(map.layers["Boss"].objects) do
            if obj.name == "gula" then sx, sy = obj.x, obj.y end
            if obj.name == "arena" then self.arena = { x = obj.x, y = obj.y, w = obj.width, h = obj.height } end
        end
        self.arena = self.arena or { x = 48, y = 80, w = 384, h = 256 }
        self.gula = spawnGula(sx, sy, self.arena)
        if data.story.gulaFrozen then
            -- still frozen where Rick left it
            self.gula:freeze()
            self.gula.freezeTime = 10
        end
    end
end

----------------------------------------------------------------------- the fight

function lairStory:startFight()
    self.fightStarted = true
    local g = self.gula
    cutscene:play(function(cs)
        cs:focus(g.x, g.y - 24)
        cs:wait(0.7)
        g:wake()
        g:say("!", {1, 0.4, 0.4}, true)
        cs:wait(0.6)
        cs:say({
            line("Gula", "Mmm... fresh meat, walking right into my feast hall."),
            line("Gula", "Rick's little friend, are you? My curse still gnaws at his belly."),
            line("Hero", "Lift his curse, or I'll break it myself!"),
            line("Gula", "Then come closer... and be my next meal!"),
        })
        -- no running away now
        self.entranceWall = spawnWall(13 * 16, 20 * 16 + 8, 64, 8)
        cs:focusPlayer()
        cs:wait(0.3)
        cs:versus(versusCards())
    end, function()
        self.fighting = true
        -- pull the camera back so Gula stays in view
        self.prevZoom = zoomTarget
        setZoomLevel(0.8)
        g:beginFight()
        showToast("Roll or Shadow Step through Gula's shockwaves and beams!", 3.5)
    end)
end

-- called by Gula at 40% health
function lairStory:onBerserk()
    self.berserk = true
    self.spare = true
    self.berserkTime = 0
    self.redFlash = 1
    showToast("Gula goes berserk!", 2.5)
end

-- the hero is down: Rick to the rescue
function lairStory:rescueScene()
    self.rescue = true
    self.berserk = false
    self.fighting = false
    self.heroDown = true
    player.health = 0
    player:setLinearVelocity(0, 0)
    local g = self.gula
    g:loom()
    g:holdMinions()

    cutscene:play(function(cs)
        -- cinema bars and a closer camera: the scene takes over
        domainFx:letterbox(true)
        setZoomLevel(1)
        shake:start(0.4, 3, 0.03)
        cs:wait(1.2)
        g:say("Now... I FEAST!", {1, 0.3, 0.3}, true)
        cs:wait(1.2)

        -- the hero is fading: eyes drift half shut
        domainFx:setEyes(0.5, 2.6)
        cs:wait(1.6)

        -- the air turns cold...
        domainFx:frost(true)
        g:say("...?", {0.8, 0.9, 1}, true)
        cs:wait(1.8)

        -- ...and Rick steps out of the passage, slowly
        local rick = spawnNPC("Rick", 15 * 16, 22 * 16, { role = "rick", sprite = "rick", scale = 0.5 })
        rick.onTalk = function() end
        rick:face(g.x)
        self:giveAura(rick)
        self.rick = rick
        -- the camera finds him standing in the cold passage...
        cs:follow(rick, -10)
        cs:wait(2.4)
        -- ...Gula's servants go first: a blink and a cut of frost each...
        for _, m in ipairs(g:liveMinions()) do
            if not m.dead and m.physics then
                local mx, my = m.physics:getPosition()
                local side = rick.x < mx and -1 or 1
                cs:walk(rick, mx + side * 12, my + 6, 260)
                rick:face(mx)
                self:rickStrike(rick, m)
                cs:wait(0.45)
            end
        end
        -- ...then he walks up to the hero, unhurried
        local tx, ty = player:getX() + 20, player:getY() + 8
        cs:walk(rick, tx, ty, math.max(26, distanceBetween(rick.x, rick.y, tx, ty) / 3.5))
        rick:face(g.x)
        -- frame them both
        cs:focus((rick.x + g.x) / 2, (rick.y + g.y) / 2 - 18)
        cs:wait(0.9)

        -- Gula turns the spell that felled the hero on Rick...
        g:say("Another meal? I'll devour you too!", {1, 0.3, 0.3}, true)
        g:chargeAt(rick)
        -- frame Gula rising over them, and Rick standing his ground
        cs:focus((rick.x + g.chargeX) / 2, (g.chargeY - 50 + rick.y) / 2)
        cs:wait(1.8)
        -- ...and before it can fire, Rick opens his domain
        -- the moment he speaks, every sound cuts out: from here on only the domain is heard
        domainFx:silence(true)
        domainFx:shout("Domain Expansion: Absolute Zero.", rick.x, rick.y - 34)
        rick.aura:surge()
        cs:wait(2.2)

        local sx, sy = cam:cameraCoords(rick.x, rick.y - 16)
        domainFx:frost(false)
        domainFx:play(sx, sy, function() return self:domainCast() end)
        rick.aura:surge()
        -- the cut-in on his eyes, then the void: Gula freezes as it closes over the hall
        cs:waitUntil(function() return domainFx:voidTime() >= domainFx.FREEZE_AT end)
        g:freeze()
        -- time stops dead, and the frozen picture cracks
        cs:wait(3.8)

        -- the hero's eyes slowly close the rest of the way...
        domainFx:closeEyes()
        cs:waitUntil(function() return not domainFx:blinking() end)
        cs:wait(1.4)

        -- ...and open again in Willowbrook
        domainFx:stop()
        data.story.gulaFrozen = true
        self.spare = false
        triggerTransition("village", WAKE.x, WAKE.y)
        player.health = data.maxHealth
        player.damagedTimer = 0
        staff:refill()
        local friend = npcs:find("Rick")
        if not friend then
            friend = spawnNPC("Rick", WAKE.x + 20, WAKE.y + 6, { role = "rick", sprite = "rick", scale = 0.42 })
        end
        friend.x, friend.y = WAKE.x + 20, WAKE.y + 6
        friend.walking = false
        friend:face(WAKE.x)
        self.friend = friend
        cs:focusPlayer()
        cs:wait(1.2)
        domainFx:openEyes()
        cs:waitUntil(function() return not domainFx:blinking() end)
        cs:wait(0.4)
        cs:say({ line("Rick", "How are you feeling?") })
        self.heroDown = false -- sits up
        cs:wait(0.3)
        cs:say({
            line("Hero", "Ahh, my head hurts a little... But more importantly, how did you...?"),
            line("Rick", "Nothing! Just something I learned on my adventures!"),
        })
        domainFx:letterbox(false)
        cs:wait(0.9)
    end, function()
        local friend = self.friend
        if friend and villageStory.RICK_AT_GUILD then
            friend.homeX, friend.homeY = villageStory.RICK_AT_GUILD.x, villageStory.RICK_AT_GUILD.y
            friend:walkTo(friend.homeX, friend.homeY, 40)
        end
        self.friend = nil
        showToast("Gula is frozen solid in its lair, and the wind has stopped... for now.", 4)
    end)
end

-- Rick arrives crackling with live lightning (src/effects/aura.lua): arcs snap
-- off him, and when a bolt strikes the ground beside him he flashes white. His
-- aura roars the whole time (updateAuraSound).
function lairStory:giveAura(rick)
    rick.aura = newAura()
    dj.play(sounds.enemies.gulaThunder, "static", "effect", 0.7, 1.15) -- he arrives with a thunderclap
    function rick:draw()
        if self.hidden then return end
        local w, h = self.sprite:getDimensions()
        local s = self.spriteScale
        local bob = math.abs(math.sin(self.bobTimer)) * (self.walking and 1.5 or 0.6)
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.ellipse("fill", self.x, self.y, 5 * math.max(1, s * 1.6), 2)
        self.aura:draw(self.x, self.y, h * s, function()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(self.sprite, self.x, self.y - bob, 0, self.scaleX * s, s, w / 2, h - 2)
        end)
        setWhite()
    end
end

-- the roar of Rick's aura: a loop while it is on, louder when he surges, and
-- deeper in slow motion
function lairStory:updateAuraSound()
    local aura = self.rick and self.rick.aura
    local volume = (aura and not pause.active) and (0.45 + 0.25 * aura.surging) or 0
    if volume > 0 and not self.auraSound then
        local ok, source = pcall(love.audio.newSource, "sounds/items/auraRoar.wav", "static")
        if ok then
            self.auraSound = source
            source:setLooping(true)
            source:play()
        end
    end
    if self.auraSound then
        if volume > 0 then
            self.auraSound:setVolume(volume)
            self.auraSound:setPitch(0.7 + 0.3 * aura.timeScale)
        else
            self.auraSound:stop()
            self.auraSound = nil
        end
    end
end

-- Rick cuts one of Gula's servants down with a sweep of frost
function lairStory:rickStrike(rick, m)
    local mx, my = m.physics:getPosition()
    m.dead = true -- enemies:destroyDead takes it away (and drops its ear)
    table.insert(self.slashes, { x = mx, y = my - 2, angle = math.atan2(my - (rick.y - 8), mx - rick.x), t = 0 })
    spawnBlast(mx, my, 14, "white", 0.2)
    for _ = 1, 10 do
        effects:spawn("damage", mx, my, { dir = vector(mx - rick.x, my - rick.y + 8) })
    end
    dj.play(sounds.items.sword, "static", "effect", 1, 0.75)
    dj.play(sounds.enemies.die, "static", "effect")
    shake:start(0.15, 2, 0.02)
end

----------------------------------------------------------------------- update

function lairStory:update(dt)
    if self.redFlash > 0 then self.redFlash = math.max(0, self.redFlash - dt * 1.5) end
    for i = #self.slashes, 1, -1 do
        local s = self.slashes[i]
        s.t = s.t + dt
        if s.t >= 0.35 then table.remove(self.slashes, i) end
    end
    if self.rick and self.rick.aura then
        -- inside his domain the lightning slows with time, and all but stops at absolute zero
        if domainFx.active then self.rick.aura.timeScale = 0.04 + 0.31 * domainFx:motion() end
        self.rick.aura:update(dt)
    end
    self:updateAuraSound()
    if self.spare and player.health < 0 then player.health = 0 end
    if not self.active or self.mapName ~= "lair" or not self.gula then return end

    self.gula:update(dt)
    -- keep Gula in frame while it fights (and looms over the fallen hero, until Rick comes)
    if self.fighting or (self.rescue and not self.rick) then
        cam.bias = cam.bias or {}
        cam.bias.x, cam.bias.y, cam.bias.weight = self.gula.x, self.gula.y - 24, 0.35
    else
        cam.bias = nil
    end
    self.displayHealth = (self.displayHealth or self.gula.health)
        + (self.gula.health - (self.displayHealth or self.gula.health)) * math.min(1, dt * 6)

    if not self.fightStarted and not data.story.gulaFrozen and not cutscene.active and curtain.state == 0
        and player:getY() < self.arena.y + self.arena.h - 30 then
        self:startFight()
    end

    if self.berserk and not self.rescue then
        self.berserkTime = self.berserkTime + dt
        -- hearts at zero, or the onslaught has gone on long enough: it lands the final blow
        if player.health <= 0 or (self.berserkTime > BERSERK_TIME and not cutscene.active) then
            self:rescueScene()
        end
    end
end

----------------------------------------------------------------------- draw

-- who stays visible inside Rick's domain, and where each one stands
function lairStory:domainCast()
    local cast = {}
    if self.gula then
        local g = self.gula
        table.insert(cast, { footY = g.y + 4, draw = function() g:draw() end })
    end
    if self.rick then
        local r = self.rick
        table.insert(cast, { footY = r.y + 1, draw = function() r:draw() end })
    end
    table.insert(cast, { footY = player:getY() + (self.heroDown and 10 or 7), draw = drawPlayer })
    return cast
end

function lairStory:drawGround()
    if not self.active then return end
    if self.mapName == "dungeon" and self.door and self.door.sealed then
        -- the cursed seal: a pulsing violet barrier of runes
        local t = love.timer.getTime()
        love.graphics.setBlendMode("add")
        for i = 0, 3 do
            love.graphics.setColor(0.65, 0.3, 1, 0.12 + 0.08 * math.sin(t * 3 + i))
            love.graphics.rectangle("fill", DOOR.x + 2, DOOR.y + 4 + i * 6, DOOR.w - 4, 4)
        end
        love.graphics.setColor(0.85, 0.6, 1, 0.5 + 0.3 * math.sin(t * 4))
        love.graphics.circle("line", DOOR.x + 16, DOOR.y + 18, 8 + math.sin(t * 2) * 1.5)
        love.graphics.setBlendMode("alpha")
        setWhite()
    elseif self.gula then
        self.gula:drawGround()
    end
end

function lairStory:collect(items)
    if self.active and self.gula then
        local g = self.gula
        table.insert(items, { y = g.y + 6, draw = function() g:draw() end })
    end
end

-- Gula's lightning and Rick's aura glow over the lair's darkness (called after it is drawn)
function lairStory:drawEmissive()
    if not (self.active and self.gula) then return end
    cam:attach()
    self.gula:drawEmissive()
    if self.rick and self.rick.aura then self.rick.aura:drawGlow() end
    cam:detach()
    self.gula:drawFlash()
end

function lairStory:drawAir()
    if self.active and self.gula then self.gula:drawAir() end
    -- Rick's frost cuts: a bright crescent that sweeps and fades
    if #self.slashes > 0 then pixelfx.world(function() self:drawSlashes() end) end
    setWhite()
end

function lairStory:drawSlashes()
    for _, s in ipairs(self.slashes) do
        local p = s.t / 0.35
        local sweep = math.min(1, p * 3)
        love.graphics.setBlendMode("add")
        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.6, 0.88, 1, 0.9 * (1 - p))
        love.graphics.arc("line", "open", s.x, s.y, 13, s.angle - 1.3, s.angle - 1.3 + 2.6 * sweep, 16)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1 - p)
        love.graphics.arc("line", "open", s.x, s.y, 10, s.angle - 1.1, s.angle - 1.1 + 2.2 * sweep, 16)
        love.graphics.setBlendMode("alpha")
    end
    setWhite()
end

function lairStory:drawHUD()
    if self.redFlash > 0 then
        love.graphics.setColor(1, 0.1, 0.1, 0.35 * self.redFlash)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
    local g = self.gula
    if not self.active or not g or not (self.fighting or self.rescue) or g.frozen then
        setWhite()
        return
    end

    local w = love.graphics.getWidth()
    local barW, barH = 120 * scale, 4 * scale
    local x, y = (w - barW) / 2, 9 * scale
    local border = math.max(2, math.floor(scale * 0.6))
    love.graphics.setFont(fonts.small)
    local title = g.berserk and "GULA, DEMON OF GLUTTONY  -  BERSERK" or "GULA, DEMON OF GLUTTONY"
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.printf(title, x + scale * 0.4, y - fonts.small:getHeight() - scale * 0.6, barW, "center")
    if g.berserk then
        love.graphics.setColor(1, 0.35 + 0.25 * math.sin(love.timer.getTime() * 10), 0.35, 1)
    else
        love.graphics.setColor(0.86, 0.66, 1, 1)
    end
    love.graphics.printf(title, x, y - fonts.small:getHeight() - scale, barW, "center")

    love.graphics.setColor(0.05, 0.04, 0.06, 0.9)
    love.graphics.rectangle("fill", x - border, y - border, barW + border * 2, barH + border * 2, scale * 0.5, scale * 0.5)
    local ratio = math.max(0, (self.displayHealth or g.health) / g.maxHealth)
    local trueRatio = math.max(0, g.health / g.maxHealth)
    love.graphics.setColor(1, 0.9, 0.7, 0.8)
    love.graphics.rectangle("fill", x, y, barW * math.max(ratio, trueRatio), barH)
    love.graphics.setColor(g.berserk and 0.95 or 0.62, 0.18, g.berserk and 0.2 or 0.86, 1)
    love.graphics.rectangle("fill", x, y, barW * math.min(ratio, trueRatio), barH)
    -- the 40% mark where it snaps
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.rectangle("fill", x + barW * 0.4 - 1, y - border, 2, barH + border * 2)
    setWhite()
end
