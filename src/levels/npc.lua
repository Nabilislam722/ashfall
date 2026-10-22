-- Villagers and other friendly characters.
-- NPC positions are the point where their feet touch the ground, which is also
-- what they are depth-sorted by against the player and the scenery.
-- A villager's look (props.sprite) is one of LOOKS: a citizen idles and walks
-- facing down, left, right or up (a row each, sprites/npc/citizens); a trader
-- stands facing you and works (one row, sprites/npc/traders). Any other sprite
-- (Rick) is a still picture that bobs.

npcs = {}

local TALK_RADIUS = 24
local FRAME = 0.15                      -- seconds a frame shows, as the pack plays them
local DOWN, LEFT, RIGHT, UP = 1, 2, 3, 4

-- w, h: a frame; ox, feet: where the feet stand in it; height: up to the top of
-- the head; face: the portrait's square in the first frame; order: the frames as
-- they play (some held), when not simply left to right
local CITIZEN = { citizen = true, w = 32, h = 32, ox = 16, feet = 28, height = 25, face = { 7, 2, 18, 18 } }
local LOOKS = {
    citizen1 = CITIZEN, citizen2 = CITIZEN, citizen3 = CITIZEN, citizen4 = CITIZEN, citizen5 = CITIZEN,
    juan = CITIZEN, hilda = CITIZEN, tom = CITIZEN, mira = CITIZEN,
    weaponTrader = { w = 32, h = 32, ox = 17, feet = 27, height = 25, face = { 9, 0, 18, 18 },
                     order = { 1, 2, 3, 4, 5, 5, 6, 7, 7, 7, 7, 8 } },
    breadTrader = { w = 32, h = 32, ox = 16, feet = 27, height = 25, face = { 7, 1, 18, 18 } },
    drinksTrader = { w = 32, h = 32, ox = 16, feet = 29, height = 26, face = { 7, 2, 18, 18 } },
    witch = { w = 48, h = 48, ox = 24, feet = 32, height = 27, face = { 14, 6, 21, 21 },
              order = { 1, 2, 3, 4, 5, 5, 5, 5, 6, 7, 8, 1 } },
}
local CITIZEN_FRAMES = { idle = { 12, 12, 12, 6 }, walk = { 6, 6, 6, 6 } }   -- per facing

-- a look's quads, cut once from its sheet(s)
local looks = {}
local function lookOf(name)
    if looks[name] ~= nil then return looks[name] end
    local spec, art = LOOKS[name], sprites.npc[name]
    if not spec or not art then
        looks[name] = false
        return false
    end
    local function row(image, r, count)
        local quads = {}
        for i = 1, count do
            quads[i] = love.graphics.newQuad((i - 1) * spec.w, (r - 1) * spec.h, spec.w, spec.h, image:getDimensions())
        end
        return quads
    end
    local look = { spec = spec }
    if spec.citizen then
        look.idle, look.walk = art.idle, art.walk
        look.idleRows, look.walkRows = {}, {}
        for r = 1, 4 do
            look.idleRows[r] = row(art.idle, r, CITIZEN_FRAMES.idle[r])
            look.walkRows[r] = row(art.walk, r, CITIZEN_FRAMES.walk[r])
        end
        look.portrait = art.idle
    else
        local cut = row(art, 1, math.floor(art:getWidth() / spec.w))
        look.image, look.frames = art, {}
        for i, f in ipairs(spec.order or cut) do
            look.frames[i] = spec.order and cut[f] or f
        end
        look.portrait = art
    end
    local f = spec.face
    look.face = love.graphics.newQuad(f[1], f[2], f[3], f[4], look.portrait:getDimensions())
    looks[name] = look
    return look
end

function spawnNPC(name, x, y, props)
    props = props or {}

    local npc = {}
    npc.name = name
    npc.role = props.role or "villager"
    npc.x = x
    npc.y = y
    npc.homeX = x
    npc.homeY = y
    npc.look = lookOf(props.sprite or "citizen1")
    if not npc.look then
        npc.sprite = sprites.npc[props.sprite]
        if not npc.sprite then npc.look = lookOf("citizen1") end
    end
    npc.spriteScale = props.scale or 1
    npc.height = npc.look and npc.look.spec.height * npc.spriteScale or npc.sprite:getHeight() * npc.spriteScale
    npc.facing = DOWN
    npc.animTime = math.random() * 3       -- villagers don't move in step
    npc.wander = props.wander or 0
    npc.wanderTimer = 1 + math.random() * 3
    npc.scaleX = 1
    npc.bobTimer = math.random() * 6
    npc.walking = false
    npc.targetX = x
    npc.targetY = y
    npc.speed = 40
    npc.scared = false
    npc.hidden = false
    npc.emote = nil
    npc.emoteTimer = 0
    npc.bubble = nil
    npc.bubbleTimer = 0

    npc.collider = world:newRectangleCollider(x - 5, y - 6, 10, 6, {collision_class = "NPC"})
    npc.collider:setType("kinematic")
    npc.collider:setFixedRotation(true)

    function npc:walkTo(tx, ty, speed)
        self.targetX = tx
        self.targetY = ty
        self.speed = speed or 40
        self.walking = true
    end

    function npc:say(text, seconds)
        self.bubble = text
        self.bubbleTimer = seconds or 2
    end

    function npc:setEmote(emote, seconds)
        self.emote = emote
        self.emoteTimer = seconds or 1.5
    end

    -- turns towards a point: a still picture flips left or right, a citizen
    -- turns whichever of its four ways is nearest (left or right without y)
    function npc:face(x, y)
        if x < self.x - 1 then
            self.scaleX = -1
        elseif x > self.x + 1 then
            self.scaleX = 1
        end
        local dx, dy = x - self.x, y and (y - self.y) or 0
        if math.abs(dx) <= 1 and math.abs(dy) <= 1 then return end
        if math.abs(dx) >= math.abs(dy) then
            self.facing = dx < 0 and LEFT or RIGHT
        else
            self.facing = dy < 0 and UP or DOWN
        end
    end

    -- the dialogue portrait: (image, quad or nil)
    function npc:portrait()
        if self.look then return self.look.portrait, self.look.face end
        return self.sprite, nil
    end

    function npc:setHidden(hidden)
        self.hidden = hidden
        self.collider:setActive(not hidden)
    end

    function npc:update(dt)
        self.bobTimer = self.bobTimer + dt * (self.scared and 14 or (self.walking and 10 or 2.5))
        self.animTime = self.animTime + dt * (self.scared and 2 or 1)

        if self.emoteTimer > 0 then
            self.emoteTimer = self.emoteTimer - dt
            if self.emoteTimer <= 0 then self.emote = nil end
        end
        if self.bubbleTimer > 0 then
            self.bubbleTimer = self.bubbleTimer - dt
            if self.bubbleTimer <= 0 then self.bubble = nil end
        end

        if self.walking then
            local dx, dy = self.targetX - self.x, self.targetY - self.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local step = self.speed * dt
            if dist <= step then
                self.x, self.y = self.targetX, self.targetY
                self.walking = false
            else
                self.x = self.x + dx / dist * step
                self.y = self.y + dy / dist * step
                self:face(self.targetX, self.targetY)
            end
        elseif self.wander > 0 and not self.scared and not isPlayerFrozen() then
            self.wanderTimer = self.wanderTimer - dt
            if self.wanderTimer <= 0 then
                self.wanderTimer = 2 + math.random() * 4
                local angle = math.random() * math.pi * 2
                local radius = math.random() * self.wander
                self:walkTo(self.homeX + math.cos(angle) * radius, self.homeY + math.sin(angle) * radius, 18)
            end
        end

        if not self.walking and distanceBetween(self.x, self.y, player:getX(), player:getY()) < 48 then
            self:face(player:getX(), player:getY())
        end

        self.collider:setPosition(self.x, self.y - 3)
    end

    function npc:draw()
        if self.hidden then return end
        local s = self.spriteScale
        if self.look then
            -- the sheet's own frames (and shadow); a scared villager trembles
            local look, spec = self.look, self.look.spec
            local image, frames = look.image, look.frames
            if spec.citizen then
                image = self.walking and look.walk or look.idle
                frames = (self.walking and look.walkRows or look.idleRows)[self.facing]
            end
            local frame = frames[math.floor(self.animTime / FRAME) % #frames + 1]
            local shake = self.scared and math.sin(self.bobTimer * 3) * 0.5 or 0
            setWhite()
            love.graphics.draw(image, frame, self.x + shake, self.y, 0, s, s, spec.ox, spec.feet)
        else
            local bob = math.abs(math.sin(self.bobTimer)) * (self.walking and 1.5 or 0.6)
            local squash = 1 + math.sin(self.bobTimer * 2) * 0.03
            local w, h = self.sprite:getDimensions()
            love.graphics.setColor(0, 0, 0, 0.25)
            love.graphics.ellipse("fill", self.x, self.y, 5 * math.max(1, s * 1.6), 2)
            setWhite()
            love.graphics.draw(self.sprite, self.x, self.y - bob, 0, self.scaleX * s, s * squash, w / 2, h - 2)
        end

        if self.emote then
            local ey = self.y - self.height - 4 - math.abs(math.sin(self.bobTimer * 2)) * 1.5
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", self.x - 3.5, ey - 7, 7, 8, 2, 2)
            love.graphics.polygon("fill", self.x - 1.5, ey + 1, self.x + 1.5, ey + 1, self.x, ey + 3)
            love.graphics.setColor(0.15, 0.1, 0.1, 1)
            if self.emote == "!" then
                love.graphics.rectangle("fill", self.x - 0.5, ey - 6, 1.2, 4)
                love.graphics.rectangle("fill", self.x - 0.5, ey - 1.2, 1.2, 1.2)
            elseif self.emote == "?" then
                love.graphics.rectangle("fill", self.x - 1.5, ey - 6, 3, 1)
                love.graphics.rectangle("fill", self.x + 1, ey - 5.5, 1, 2)
                love.graphics.rectangle("fill", self.x - 0.5, ey - 3.5, 1.5, 1)
                love.graphics.rectangle("fill", self.x - 0.5, ey - 1.2, 1.2, 1.2)
            elseif self.emote == "heart" then
                love.graphics.setColor(0.86, 0.2, 0.25, 1)
                love.graphics.circle("fill", self.x - 1.2, ey - 4, 1.4)
                love.graphics.circle("fill", self.x + 1.2, ey - 4, 1.4)
                love.graphics.polygon("fill", self.x - 2.6, ey - 3.6, self.x + 2.6, ey - 3.6, self.x, ey - 0.8)
            end
            setWhite()
        end
    end

    -- screen-space speech bubble, drawn after the camera
    function npc:drawBubble()
        if self.hidden or not self.bubble then return end
        local sx, sy = cam:cameraCoords(self.x, self.y - self.height - 6)
        love.graphics.setFont(fonts.float)
        local tw = fonts.float:getWidth(self.bubble) + 3 * scale
        local th = fonts.float:getHeight() + scale
        love.graphics.setColor(1, 0.98, 0.92, 0.95)
        love.graphics.rectangle("fill", sx - tw / 2, sy - th, tw, th, scale * 0.6, scale * 0.6)
        love.graphics.polygon("fill", sx - scale, sy, sx + scale, sy, sx, sy + scale * 1.2)
        love.graphics.setColor(0.15, 0.1, 0.1, 1)
        love.graphics.print(self.bubble, sx - tw / 2 + 1.5 * scale, sy - th + scale * 0.4)
        setWhite()
    end

    function npc:destroy()
        if self.collider then
            self.collider:destroy()
            self.collider = nil
        end
    end

    table.insert(npcs, npc)
    return npc
end

function npcs:update(dt)
    for _, n in ipairs(npcs) do
        n:update(dt)
    end
end

function npcs:find(name)
    for _, n in ipairs(npcs) do
        if n.name == name then return n end
    end
end

function npcs:clear()
    for i = #npcs, 1, -1 do
        npcs[i]:destroy()
        table.remove(npcs, i)
    end
end

function npcs:remove(npc)
    for i = #npcs, 1, -1 do
        if npcs[i] == npc then
            npc:destroy()
            table.remove(npcs, i)
        end
    end
end

-- adds every visible NPC to the depth-sorted draw list
function npcs:collect(items)
    for _, n in ipairs(npcs) do
        if not n.hidden then
            table.insert(items, { y = n.y, draw = n.draw, arg = n })
        end
    end
end

function npcs:getInteractable()
    if isPlayerFrozen() then return nil end
    local best, bestDist = nil, TALK_RADIUS
    for _, n in ipairs(npcs) do
        if not n.hidden and n.onTalk then
            local d = distanceBetween(n.x, n.y - 6, player:getX(), player:getY())
            if d < bestDist then
                best, bestDist = n, d
            end
        end
    end
    return best
end

function npcs:tryInteract()
    local n = self:getInteractable()
    if not n then return false end
    n:face(player:getX(), player:getY())
    n.walking = false
    n.onTalk(n)
    return true
end

function npcs:drawOverlay()
    for _, n in ipairs(npcs) do
        n:drawBubble()
    end

    local n = self:getInteractable()
    if not n or pause.active then return end
    local sx, sy = cam:cameraCoords(n.x, n.y - n.height - 4)
    local label = n.talkLabel or "Talk"
    local text = "[E] " .. label
    love.graphics.setFont(fonts.float)
    local tw = fonts.float:getWidth(text) + 3 * scale
    local th = fonts.float:getHeight() + scale
    local bob = math.sin(love.timer.getTime() * 5) * scale * 0.6
    love.graphics.setColor(0.05, 0.04, 0.06, 0.85)
    love.graphics.rectangle("fill", sx - tw / 2, sy - th + bob, tw, th, scale * 0.6, scale * 0.6)
    love.graphics.setColor(1, 0.9, 0.55, 1)
    love.graphics.print(text, sx - tw / 2 + 1.5 * scale, sy - th + scale * 0.4 + bob)
    setWhite()
end
