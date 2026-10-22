-- Buildings and other big things made of tiles (Willowbrook's houses, its
-- tavern and windmill, fences, carts, crops, fruit trees and farm animals):
-- each object in a map's "Structures" layer is a rectangle, and the tiles of
-- its family's tile layers ("Struct<family>_<n>", drawn by this module, not by
-- STI) inside that rectangle make one picture, depth-sorted with the world at
-- its foot (the rectangle's bottom, or its sortY property). So the hero walks
-- behind a house and in front of it, and its roof hides them back there.
-- Structures that overlap belong to different families, so every tile knows
-- whose it is. Animated tiles (sails, smoke, banners, doors, animals) play on.
-- Their colliders are ordinary walls in the map's Walls layer.
-- A structure's still tiles are drawn from sprite batches (one per run of tiles
-- from the same sheet, in layer order), so a house costs a few draws, not a
-- few dozen; its animated tiles are drawn one by one, at the frame the clock says.

structures = { list = {}, map = nil }

-- "Struct2_3" -> 2
local function familyOf(layer)
    if layer.type ~= "tilelayer" then return nil end
    return tonumber(layer.name:match("^Struct(%d+)_%d+$"))
end

function structures.isLayer(layer)
    return familyOf(layer) ~= nil
end

function structures:setMap(map)
    self.list = {}
    self.map = map
    if not map or not map.layers["Structures"] then return end
    local byFamily = {}
    for _, o in ipairs(map.layers["Structures"].objects) do
        local props = o.properties or {}
        local s = { name = o.name, x = o.x, y = o.y, w = o.width, h = o.height,
            sortY = tonumber(props.sortY) or (o.y + o.height), cells = {} }
        local family = tonumber(props.family) or 1
        byFamily[family] = byFamily[family] or {}
        table.insert(byFamily[family], s)
        table.insert(self.list, s)
    end
    local tw, th = map.tilewidth, map.tileheight
    for _, layer in ipairs(map.layers) do
        local family = familyOf(layer)
        local members = family and byFamily[family]
        if members then
            for y, row in pairs(layer.data) do
                for x, tile in pairs(row) do
                    local cx, cy = (x - 1) * tw + tw / 2, (y - 1) * th + th / 2
                    for _, s in ipairs(members) do
                        if cx >= s.x and cx < s.x + s.w and cy >= s.y and cy < s.y + s.h then
                            local sx, sy = map.flipShift(tile)
                            table.insert(s.cells, { tile = tile, x = (x - 1) * tw + tile.offset.x + sx, y = (y - 1) * th + tile.offset.y + sy })
                            break
                        end
                    end
                end
            end
        end
    end
end

-- an animated tile's frame at this moment (ms), by the clock: STI steps only
-- the tiles in its own batches
local function frameAt(tile, ms)
    local animation = tile.animation
    if not tile.cycle then
        tile.cycle = 0
        for _, f in ipairs(animation) do tile.cycle = tile.cycle + tonumber(f.duration) end
    end
    if tile.cycle <= 0 then return animation[1] end
    local t = ms % tile.cycle
    for _, f in ipairs(animation) do
        t = t - tonumber(f.duration)
        if t < 0 then return f end
    end
    return animation[#animation]
end

-- its tiles in runs: consecutive still tiles from one sheet share a sprite batch,
-- an animated tile is a run of its own (made the first time it's drawn)
local function buildRuns(s)
    local map = structures.map
    s.runs = {}
    local run
    for _, c in ipairs(s.cells) do
        local tile = c.tile
        local image = map.tilesets[tile.tileset].image
        if tile.animation then
            table.insert(s.runs, { cell = c, image = image })
            run = nil
        else
            if not run or run.image ~= image then
                run = { image = image, cells = {} }
                table.insert(s.runs, run)
            end
            table.insert(run.cells, c)
        end
    end
    for _, r in ipairs(s.runs) do
        if r.cells then
            r.batch = love.graphics.newSpriteBatch(r.image, #r.cells, "static")
            for _, c in ipairs(r.cells) do
                r.batch:add(c.tile.quad, c.x, c.y, c.tile.r, c.tile.sx, c.tile.sy)
            end
            r.cells = nil
        end
    end
end

local function drawStructure(s)
    local map = structures.map
    if not s.runs then buildRuns(s) end
    setWhite()
    local ms = love.timer.getTime() * 1000
    for _, r in ipairs(s.runs) do
        if r.batch then
            love.graphics.draw(r.batch)
        else
            local c = r.cell
            local tile = c.tile
            local frame = frameAt(tile, ms)
            local shown = frame and map.tiles[tonumber(frame.tileid) + map.tilesets[tile.tileset].firstgid]
            love.graphics.draw(r.image, shown and shown.quad or tile.quad, c.x, c.y, tile.r, tile.sx, tile.sy)
        end
    end
end

-- every structure in view, for the depth-sorted world (src/draw.lua)
function structures:collect(items)
    if #self.list == 0 then return end
    local x0, y0 = cam:worldCoords(0, 0)
    local x1, y1 = cam:worldCoords(love.graphics.getWidth(), love.graphics.getHeight())
    for _, s in ipairs(self.list) do
        if s.x < x1 + 16 and s.x + s.w > x0 - 16 and s.y < y1 + 16 and s.y + s.h > y0 - 16 then
            table.insert(items, { y = s.sortY, draw = drawStructure, arg = s })
        end
    end
end

-- all of them, unsorted (the minimap's picture of the map)
function structures:drawAll()
    table.sort(self.list, function(a, b) return a.sortY < b.sortY end)
    for _, s in ipairs(self.list) do drawStructure(s) end
end
