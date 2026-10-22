-- Minimap in the top-right corner, under the ☰ button. Press N to hide it.
--
-- The map picture is drawn once per map (tile layers scaled down, with solid
-- things like houses, trees and fences darkened). Markers are drawn live:
-- you, exits, checkpoints, Rick during the plaza fight, Master Juan once a
-- villager has pointed the way to him, and whatever Rick's story points to next
-- (Rick himself, the inn, or the Adventurers' Guild, highlighted). Under the map:
-- its name, and the day and time of day.

local webBridge = require("src/utilities/webBridge")

minimap = {}
minimap.visible = true
minimap.canvas = nil

local SHRINK = 8 -- world pixels per minimap pixel

local MAP_NAMES = {
    test = "Willow Meadow",
    village = "Willowbrook",
    woods = "Whispering Woods",
    dungeon = "Old Dungeon",
    lair = "Gula's Lair",
    testCave = "Cave",
    test2 = "Forest Clearing",
}

function minimap:build(map, mapName)
    self.mapName = mapName
    self.mapW = map.width * map.tilewidth
    self.mapH = map.height * map.tileheight
    local cw, ch = math.ceil(self.mapW / SHRINK), math.ceil(self.mapH / SHRINK)

    self.canvas = love.graphics.newCanvas(cw, ch)
    self.canvas:setFilter("linear", "linear")

    love.graphics.push("all")
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0.08, 0.08, 0.1, 1)
    love.graphics.origin()
    love.graphics.scale(1 / SHRINK)
    setWhite()
    for _, layer in ipairs(map.layers) do
        -- the ground, and the forest's scenery flattened onto it
        if isGroundLayer(layer) or forestDecor.isPropLayer(layer) then
            map:drawLayer(layer)
        end
    end
    structures:drawAll() -- houses, trees and fences, flattened onto it too
    -- solid scenery darker, so paths and clearings stand out
    love.graphics.setColor(0.04, 0.05, 0.08, 0.5)
    for _, wall in ipairs(walls) do
        if wall.rect and wall.type ~= "ground" then
            love.graphics.rectangle("fill", wall.rect.x, wall.rect.y, wall.rect.w, wall.rect.h)
        end
    end
    love.graphics.pop()

    self.exits = {}
    if map.layers["Transitions"] then
        for _, obj in ipairs(map.layers["Transitions"].objects) do
            table.insert(self.exits, { x = obj.x + obj.width / 2, y = obj.y + obj.height / 2 })
        end
    end
end

function minimap:clear()
    self.canvas = nil
end

-- screen rectangle of the minimap, or nil when it is hidden
function minimap:rect()
    if not self.canvas or not self.visible or gamestate ~= 1 or pause.active then return nil end
    local hs = hudScale()
    local cw, ch = self.canvas:getDimensions()
    local s = math.min(62 * hs / cw, 40 * hs / ch)
    local w, h = cw * s, ch * s
    local x = love.graphics.getWidth() - w - 6
    local y = 6 + 13 * hs + 3 * hs
    if webBridge.hasPageMenu() then y = 6 end -- no in-game menu button above it
    return x, y, w, h, s
end

function minimap:draw()
    local x, y, w, h, s = self:rect()
    if not x then return end
    local hs = hudScale()

    local function toScreen(wx, wy)
        local mx = x + math.max(0, math.min(self.mapW, wx)) / SHRINK * s
        local my = y + math.max(0, math.min(self.mapH, wy)) / SHRINK * s
        return mx, my
    end

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - 3, y - 3, w + 6, h + 6, hs, hs)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.draw(self.canvas, x, y, 0, s, s)
    love.graphics.setLineWidth(math.max(2, math.floor(hs * 0.5)))
    love.graphics.setColor(0.93, 0.84, 0.62, 0.9)
    love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, hs, hs)

    local t = love.timer.getTime()
    local dot = math.max(3, hs * 1.3)

    -- exits
    love.graphics.setColor(0.45, 0.95, 0.55, 1)
    for _, exit in ipairs(self.exits) do
        local ex, ey = toScreen(exit.x, exit.y)
        love.graphics.circle("fill", ex, ey, dot * 0.9)
    end

    -- checkpoints
    for _, cp in ipairs(checkpoints) do
        local cx, cy = toScreen(cp.x, cp.y)
        if data.checkpoints[cp.key] then
            love.graphics.setColor(1, 0.45, 0.1, 1)
        else
            love.graphics.setColor(0.75, 0.82, 0.95, 1)
        end
        love.graphics.polygon("fill", cx, cy - dot * 1.2, cx + dot, cy, cx, cy + dot * 1.2, cx - dot, cy)
    end

    -- Rick while he's still around
    if villageStory.active and villageStory.rick then
        local rx, ry = toScreen(villageStory.rick.x, villageStory.rick.y)
        love.graphics.setColor(0.95, 0.25, 0.2, 1)
        love.graphics.circle("fill", rx, ry, dot * (1.3 + math.sin(t * 6) * 0.2))
    end

    -- Master Juan, once a villager has pointed the way
    if self.mapName == "village" and data.story.masterHinted and not data.skills.shadowStep then
        local juan = npcs:find("Master Juan")
        if juan then
            local kx, ky = toScreen(juan.x, juan.y)
            local pulse = 1 + math.sin(t * 5) * 0.25
            love.graphics.setColor(0.6, 0.35, 0.95, 1)
            love.graphics.circle("fill", kx, ky, dot * 1.6 * pulse)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(fonts.hudSmall)
            love.graphics.printf("!", kx - dot * 2, ky - fonts.hudSmall:getHeight() / 2, dot * 4, "center")
        end
    end

    -- the next step of Rick's story: someone to talk to, or the guild hall lit up
    if self.mapName == "village" then
        local gx, gy, kind = villageStory:objectiveTarget()
        if gx then
            local pulse = 1 + math.sin(t * 5) * 0.25
            if kind == "guild" then
                local hall = villageStory.GUILD_HALL
                local x0, y0 = toScreen(hall.x - hall.w / 2, hall.y - hall.h / 2)
                local x1, y1 = toScreen(hall.x + hall.w / 2, hall.y + hall.h / 2)
                love.graphics.setColor(1, 0.8, 0.25, 0.3 + 0.15 * math.sin(t * 5))
                love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
                love.graphics.setColor(1, 0.86, 0.3, 1)
                love.graphics.rectangle("line", x0 - pulse, y0 - pulse, x1 - x0 + pulse * 2, y1 - y0 + pulse * 2)
            end
            local mx, my = toScreen(gx, gy)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.circle("fill", mx, my, dot * 1.9 * pulse)
            love.graphics.setColor(1, 0.78, 0.2, 1)
            love.graphics.circle("fill", mx, my, dot * 1.6 * pulse)
            love.graphics.setColor(0.2, 0.1, 0, 1)
            love.graphics.setFont(fonts.hudSmall)
            love.graphics.printf("!", mx - dot * 2, my - fonts.hudSmall:getHeight() / 2, dot * 4, "center")
        end
    end

    -- you
    local px, py = toScreen(player:getX(), player:getY())
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", px, py, dot * 1.25)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", px, py, dot * 0.85)

    -- map name
    local name = MAP_NAMES[self.mapName] or self.mapName
    love.graphics.setFont(fonts.hudGoal)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.printf(name, x - 3 + 1.5, y + h + 3 + 1.5, w + 6, "right")
    love.graphics.setColor(0.93, 0.84, 0.62, 1)
    love.graphics.printf(name, x - 3, y + h + 3, w + 6, "right")

    -- the day and the time of day
    local font = fonts.hudGoal
    local when = "Day " .. data.day .. " - " .. worldClock:phase()
    local wx, wy = x + w + 3 - font:getWidth(when), y + h + 3 + font:getHeight()
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.print(when, wx + 1.5, wy + 1.5)
    if worldClock:isNight() then love.graphics.setColor(0.7, 0.78, 1, 1) else love.graphics.setColor(1, 0.92, 0.7, 1) end
    love.graphics.print(when, wx, wy)

    love.graphics.setLineWidth(1)
    setWhite()
end
