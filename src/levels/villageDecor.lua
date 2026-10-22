-- Tiny Swords scenery (houses, trees, bushes, rocks) placed in a map's
-- "Decorations" object layer, plus Willowbrook's windmill and gatehouses. Each piece gets a
-- collider at its base and is depth-sorted against the player, villagers and
-- Rick. When the wind blows (src/effects/wind.lua) the trees sway and lean with
-- it and the windmill's sails turn.

villageDecor = {
    active = false,
    drawList = {},
    treeQuads = {},
    bushQuads = {}
}

local BUILDING_SCALE = 0.60
local TREE_SCALE = 0.52
local BUSH_SCALE = 0.58
local ROCK_SCALE = 0.72

local TREE_ORIGIN_X, TREE_ORIGIN_Y = 96, 224
local BUSH_ORIGIN_X, BUSH_ORIGIN_Y = 64, 90
local ROCK_ORIGIN_X, ROCK_ORIGIN_Y = 32, 48

local function makeFrames(image, frameWidth, frameHeight)
    local frames = {}
    local count = math.floor(image:getWidth() / frameWidth)

    for frame = 1, count do
        frames[frame] = love.graphics.newQuad(
            (frame - 1) * frameWidth,
            0,
            frameWidth,
            frameHeight,
            image:getWidth(),
            image:getHeight()
        )
    end

    return frames
end

local function drawEntry(entry)
    setWhite()

    if entry.kind == "building" then
        love.graphics.draw(entry.sprite, entry.x, entry.y, 0, entry.scale, entry.scale)
    elseif entry.kind == "tree" then
        local image = entry.frame % 2 == 0 and sprites.village.trees2 or sprites.village.trees1
        local quads = villageDecor.treeQuads
        local frame, lean = entry.frame, 0
        if wind.strength > 0.02 then
            -- the sheet's frames are a sway: play them, faster in a gust, and lean downwind
            frame = entry.frame + math.floor(wind.t * (5 + 7 * wind.strength) + entry.x * 0.07)
            lean = -wind.strength * (0.05 + 0.03 * math.sin(wind.t * 1.9 + entry.x * 0.05))
        end
        love.graphics.draw(image, quads[((frame - 1) % #quads) + 1], entry.x, entry.y, 0, TREE_SCALE, TREE_SCALE, TREE_ORIGIN_X, TREE_ORIGIN_Y, lean, 0)
    elseif entry.kind == "bush" then
        local image = entry.frame % 2 == 0 and sprites.village.bushes2 or sprites.village.bushes1
        local quads = villageDecor.bushQuads
        love.graphics.draw(image, quads[((entry.frame - 1) % #quads) + 1], entry.x, entry.y, 0, BUSH_SCALE, BUSH_SCALE, BUSH_ORIGIN_X, BUSH_ORIGIN_Y)
    elseif entry.kind == "rock" then
        love.graphics.draw(entry.sprite, entry.x, entry.y, 0, ROCK_SCALE, ROCK_SCALE, ROCK_ORIGIN_X, ROCK_ORIGIN_Y)
    elseif entry.kind == "stall" then
        love.graphics.draw(entry.sprite, entry.x, entry.y)
    elseif entry.kind == "gate" then
        love.graphics.draw(entry.sprite, entry.x, entry.y)
    elseif entry.kind == "windmill" then
        love.graphics.draw(sprites.village.windmill, entry.x, entry.y)
        local sails = sprites.village.windmillSails
        local w, h = sails:getDimensions()
        love.graphics.draw(sails, entry.x + 24, entry.y + 17, villageDecor.sailAngle, 1, 1, w / 2, h / 2)
    end
end

-- the windmill turns slowly on a calm day, and briskly in the wind
villageDecor.sailAngle = 0
function villageDecor:update(dt)
    self.sailAngle = self.sailAngle + dt * (0.25 + 2.2 * wind.strength)
end

function villageDecor:setMap(map, mapName)
    self.drawList = {}
    self.active = map ~= nil and map.layers["Decorations"] ~= nil

    if not self.active then return end

    if #self.treeQuads == 0 then
        self.treeQuads = makeFrames(sprites.village.trees1, 192, 256)
        self.bushQuads = makeFrames(sprites.village.bushes1, 128, 128)
    end

    for _, decoration in ipairs(map.layers["Decorations"].objects) do
        local properties = decoration.properties or {}
        local x, y = decoration.x, decoration.y

        if decoration.type == "building" then
            local sprite = sprites.village[properties.sprite]
            if sprite then
                local buildingScale = tonumber(properties.scale) or BUILDING_SCALE
                local width = sprite:getWidth() * buildingScale
                local height = sprite:getHeight() * buildingScale
                table.insert(self.drawList, { kind = "building", sprite = sprite, x = x, y = y, scale = buildingScale, sortY = y + height - 6 })
                spawnWall(x + width * 0.08, y + height * 0.52, width * 0.84, height * 0.40)
            end
        elseif decoration.type == "tree" then
            table.insert(self.drawList, { kind = "tree", x = x, y = y, frame = properties.frame or 1, sortY = y })
            spawnWall(x - 9, y - 12, 18, 10)
        elseif decoration.type == "bush" then
            table.insert(self.drawList, { kind = "bush", x = x, y = y, frame = properties.frame or 1, sortY = y - 6 })
            spawnWall(x - 12, y - 14, 24, 8)
        elseif decoration.type == "stall" then
            -- pixel-scale market stall sprite, drawn from its top-left corner;
            -- only the counter at the bottom blocks the player
            local sprite = sprites.village[properties.sprite]
            if sprite then
                local width, height = sprite:getDimensions()
                table.insert(self.drawList, { kind = "stall", sprite = sprite, x = x, y = y, sortY = y + height - 8 })
                spawnWall(x + 2, y + height - 36, width - 4, 32)
            end
        elseif decoration.type == "gate" then
            -- a gatehouse, drawn from its top-left corner and sorted by its base:
            -- you pass under its roof band, and its walls hide whoever stands
            -- behind them (the map's Walls layer holds its colliders)
            local sprite = sprites.village[properties.sprite or "gate"]
            if sprite then
                table.insert(self.drawList, { kind = "gate", sprite = sprite, x = x, y = y, sortY = y + sprite:getHeight() - 2 })
            end
        elseif decoration.type == "windmill" then
            -- drawn from its top-left corner; the stone base blocks
            table.insert(self.drawList, { kind = "windmill", x = x, y = y, sortY = y + 72 })
            spawnWall(x + 4, y + 58, 40, 14)
        elseif decoration.type == "rock" then
            local sprite = sprites.village[properties.sprite or "rock1"]
            if sprite then
                table.insert(self.drawList, { kind = "rock", sprite = sprite, x = x, y = y, sortY = y - 2 })
                spawnWall(x - 13, y - 10, 26, 11)
            end
        end
    end
end

-- adds every decoration to the depth-sorted draw list
function villageDecor:collect(items)
    if not self.active then return end
    for _, entry in ipairs(self.drawList) do
        table.insert(items, { y = entry.sortY, draw = drawEntry, arg = entry })
    end
end
