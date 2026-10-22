-- F3: the developer panel. It shows what's going on (frame time, memory, the
-- map, the hero, how many of everything) and switches helpers on and off with
-- the number keys while it's open; they stay on after it closes:
--   1  colliders: every physics box, by kind (see COLORS), and the high ground
--   2  depth lines: the line each thing sorts at, in front of or behind the hero
--   3  monsters: state, health, and how far off they notice the hero
--   4  tile grid, and the tile under the cursor
--   5  god mode: nothing hurts, and you walk through walls
--   6  game speed: 1x, 0.5x, 0.25x, 2x
--   7  heal, and refill mana
--   8  teleport to the cursor

devTools = { open = false, show = {}, speed = 1 }

local SPEEDS = { 1, 0.5, 0.25, 2 }
local COLORS = {
    Wall = { 1, 0.25, 0.25 },        -- walls
    ground = { 0.3, 0.6, 1 },        -- water (walls of type "ground": arrows fly over)
    scenery = { 1, 0.65, 0.15 },     -- trees, rocks, ruins... (src/levels/forestDecor.lua)
    Enemy = { 1, 0.3, 1 },
    Player = { 0.3, 1, 0.4 },
    FreePlayer = { 0.3, 1, 0.4 },
    Transition = { 1, 1, 0.3 },
    NPC = { 0.3, 1, 1 },
    other = { 0.85, 0.85, 0.85 },
    high = { 0.65, 1, 0.65 },        -- high ground: the camera draws back up there
}

function devTools:timeScale()
    return SPEEDS[self.speed]
end

function devTools:setGod(on)
    godMode = on
    player:setCollisionClass(godMode and "FreePlayer" or "Player")
    player.damagedTimer = 0
end

-- returns true when it used the key
function devTools:keypressed(key)
    if key == "f3" then
        self.open = not self.open
        return true
    end
    if not self.open or gamestate ~= 1 then return false end
    if key == "1" then self.show.colliders = not self.show.colliders
    elseif key == "2" then self.show.depth = not self.show.depth
    elseif key == "3" then self.show.monsters = not self.show.monsters
    elseif key == "4" then self.show.grid = not self.show.grid
    elseif key == "5" then self:setGod(not godMode)
    elseif key == "6" then self.speed = self.speed % #SPEEDS + 1
    elseif key == "7" then
        player.health = data.maxHealth
        staff.mana = staff:maxMana()
    elseif key == "8" then
        player:setPosition(cam:mousePosition())
        player:setLinearVelocity(0, 0)
    else
        return false
    end
    return true
end

local function view()
    local x0, y0 = cam:worldCoords(0, 0)
    local x1, y1 = cam:worldCoords(love.graphics.getWidth(), love.graphics.getHeight())
    return x0 - 32, y0 - 32, x1 + 32, y1 + 32
end

local function colorOf(collider)
    if collider.scenery then return COLORS.scenery end
    if collider.type == "ground" then return COLORS.ground end
    return COLORS[collider.collision_class] or COLORS.other
end

-- every collider in view, outlined in its kind's colour, and the high ground
function devTools:drawColliders()
    local vx0, vy0, vx1, vy1 = view()
    love.graphics.setLineWidth(1 / getRenderScale())
    local hc = COLORS.high
    for _, r in ipairs(highGround.rects) do
        love.graphics.setColor(hc[1], hc[2], hc[3], r.stairs and 0.16 or 0.08)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
        love.graphics.setColor(hc[1], hc[2], hc[3], 0.5)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
    end
    for _, body in ipairs(world.box2d_world:getBodies()) do
        local bx, by = body:getPosition()
        for _, fixture in ipairs(body:getFixtures()) do
            local collider = fixture:getUserData()
            if not fixture:isSensor() and type(collider) == "table" then
                local shape = fixture:getShape()
                local c = colorOf(collider)
                if shape:type() == "PolygonShape" then
                    local pts = { body:getWorldPoints(shape:getPoints()) }
                    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                    for i = 1, #pts, 2 do
                        minX, maxX = math.min(minX, pts[i]), math.max(maxX, pts[i])
                        minY, maxY = math.min(minY, pts[i + 1]), math.max(maxY, pts[i + 1])
                    end
                    if maxX >= vx0 and minX <= vx1 and maxY >= vy0 and minY <= vy1 then
                        love.graphics.setColor(c[1], c[2], c[3], 0.18)
                        love.graphics.polygon("fill", pts)
                        love.graphics.setColor(c[1], c[2], c[3], 0.9)
                        love.graphics.polygon("line", pts)
                    end
                elseif shape:type() == "CircleShape" then
                    local sx, sy = shape:getPoint()
                    love.graphics.setColor(c[1], c[2], c[3], 0.9)
                    love.graphics.circle("line", bx + sx, by + sy, shape:getRadius())
                end
            end
        end
    end
end

-- the line each thing sorts at: whoever stands below it is drawn in front
function devTools:drawDepth()
    love.graphics.setLineWidth(1 / getRenderScale())
    love.graphics.setColor(1, 0.65, 0.15, 0.9)
    for _, p in ipairs(forestDecor.props) do
        love.graphics.line(p.x, p.sortY, p.x + p.w, p.sortY)
    end
    love.graphics.setColor(1, 0.3, 1, 0.9)
    for _, e in ipairs(enemies) do
        if e.physics then
            local ex, ey = e.physics:getPosition()
            love.graphics.line(ex - 8, ey + 4, ex + 8, ey + 4)
        end
    end
    love.graphics.setColor(0.3, 1, 0.4, 1)
    love.graphics.line(player:getX() - 8, player:getY() + 6, player:getX() + 8, player:getY() + 6)
end

function devTools:drawMonsters()
    love.graphics.setLineWidth(1 / getRenderScale())
    for _, e in ipairs(enemies) do
        if e.physics then
            local ex, ey = e.physics:getPosition()
            love.graphics.setColor(1, 0.3, 1, e.state >= 99 and 0.5 or 0.2)
            love.graphics.circle("line", ex, ey, e.aggroRange or 54)
        end
    end
end

function devTools:drawGrid()
    local vx0, vy0, vx1, vy1 = view()
    local tw, th = gameMap.tilewidth, gameMap.tileheight
    love.graphics.setLineWidth(1 / getRenderScale())
    love.graphics.setColor(1, 1, 1, 0.12)
    for x = math.floor(vx0 / tw) * tw, vx1, tw do love.graphics.line(x, vy0, x, vy1) end
    for y = math.floor(vy0 / th) * th, vy1, th do love.graphics.line(vx0, y, vx1, y) end
    local mx, my = cam:mousePosition()
    love.graphics.setColor(1, 1, 0.3, 0.5)
    love.graphics.rectangle("line", math.floor(mx / tw) * tw, math.floor(my / th) * th, tw, th)
end

-- in the world, with the camera attached
function devTools:drawWorld()
    if gamestate ~= 1 or not gameMap then return end
    love.graphics.push("all")
    if self.show.grid then self:drawGrid() end
    if self.show.colliders then self:drawColliders() end
    if self.show.monsters then self:drawMonsters() end
    if self.show.depth then self:drawDepth() end
    love.graphics.pop()
end

local function count(list)
    local n = 0
    for _ in ipairs(list or {}) do n = n + 1 end
    return n
end

-- on the screen: monster labels, and the panel when it's open
function devTools:drawScreen()
    if gamestate ~= 1 or not gameMap then return end
    love.graphics.push("all")
    love.graphics.setFont(fonts.dev)
    if self.show.monsters then
        for _, e in ipairs(enemies) do
            if e.physics then
                local sx, sy = cam:cameraCoords(e.physics:getX(), e.physics:getY() - 24)
                local text = string.format("%s%s hp %.1f  %s%s", e.type, e.form and (" " .. e.form) or "", e.health,
                    tostring(e.state), e.mode and (" " .. e.mode) or "")
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.rectangle("fill", sx - 4, sy - 2, fonts.dev:getWidth(text) + 8, 16)
                love.graphics.setColor(1, 0.7, 1, 1)
                love.graphics.print(text, sx, sy)
            end
        end
    end
    if self.open then self:drawPanel() end
    love.graphics.pop()
end

function devTools:drawPanel()
    local stats = love.graphics.getStats()
    local px, py = player:getPosition()
    local tw, th = gameMap.tilewidth, gameMap.tileheight
    local mx, my = cam:mousePosition()
    local on = function(v) return v and "ON" or "off" end
    local lines = {
        { "DEVELOPER  -  F3 to close", { 1, 0.86, 0.35 } },
        { string.format("fps %d   frame %.1f ms   draw calls %d   memory %.1f MB", love.timer.getFPS(),
            love.timer.getAverageDelta() * 1000, stats.drawcalls, collectgarbage("count") / 1024) },
        { string.format("map %s  %dx%d tiles   %s, day %d   zoom %.2fx   height %.0f%%  (view %.2fx)", loadedMap or "?",
            gameMap.width, gameMap.height, worldClock:phase(), data.day or 1, zoomLevel, highGround.amount * 100, highGround:zoom()) },
        { string.format("hero %.0f, %.0f  (tile %d, %d)   state %s   hp %.1f/%d   stamina %.0f   mana %.0f/%d", px, py,
            math.floor(px / tw), math.floor(py / th), tostring(player.state), player.health, data.maxHealth,
            player.stamina or 0, staff.mana, staff:maxMana()) },
        { string.format("cursor %.0f, %.0f  (tile %d, %d)", mx, my, math.floor(mx / tw), math.floor(my / th)) },
        { string.format("walls %d   monsters %d   scenery %d   npcs %d   effects %d   loot %d", count(walls), count(enemies),
            count(forestDecor.props), count(npcs), count(effects), count(loots)) },
        { "" },
        { "1  colliders      " .. on(self.show.colliders) },
        { "2  depth lines    " .. on(self.show.depth) },
        { "3  monsters       " .. on(self.show.monsters) },
        { "4  tile grid      " .. on(self.show.grid) },
        { "5  god mode       " .. on(godMode) .. "   (no damage, walk through walls)" },
        { "6  game speed     " .. SPEEDS[self.speed] .. "x" },
        { "7  heal and refill mana" },
        { "8  teleport to the cursor" },
    }
    if self.show.colliders then
        table.insert(lines, { "   walls red, water blue, scenery orange, monsters pink, hero green, exits yellow, high ground light green", { 0.7, 0.7, 0.7 } })
    end
    local lineHeight, width = 16, 0
    for _, l in ipairs(lines) do width = math.max(width, fonts.dev:getWidth(l[1])) end
    local x, y = 12, 120
    love.graphics.setColor(0.02, 0.03, 0.04, 0.88)
    love.graphics.rectangle("fill", x, y, width + 20, #lines * lineHeight + 12)
    love.graphics.setColor(0.25, 0.75, 0.68, 1)
    love.graphics.rectangle("line", x, y, width + 20, #lines * lineHeight + 12)
    for i, l in ipairs(lines) do
        local c = l[2] or { 0.88, 0.92, 0.88 }
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.print(l[1], x + 10, y + 6 + (i - 1) * lineHeight)
    end
end
