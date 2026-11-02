-- The places of the world, in one list: their names (the title screen, the
-- minimap and the Adventure Book all read them here), a line about each, the
-- picture and marker the book shows for them, where they sit on the book's
-- island map, and the roads between them (the maps' Transitions layers).
--
-- data.visited holds the places the hero has been ("map" = true): loadMap
-- marks them, and the book only shows a place once it's been found (or a road
-- from a found place leads to it).

places = {}

-- art: the medallion and marker in sprites/ui/book/places.png ("fortress",
-- "cave", "cabin", "lake", "ruins"); x, y: on the island picture (103 x 102)
places.LIST = {
    { id = "test", name = "Willow Meadow", art = "ruins", x = 58, y = 47,
      about = "Green hills around an old shrine. Every road in the land starts here.",
      links = { "village", "woods", "test2", "testCave" } },
    { id = "village", name = "Willowbrook", art = "cabin", x = 70, y = 70,
      about = "A farming village of good bread and better gossip. The Adventurers' Guild keeps a hall here.",
      links = { "test", "dungeon" } },
    { id = "woods", name = "Whispering Woods", art = "lake", x = 38, y = 63,
      about = "Old trees, a still lake, and slimes in every colour. Rest at the shrine by the water.",
      links = { "test" } },
    { id = "test2", name = "Forest Clearing", art = "ruins", x = 36, y = 30,
      about = "Ruined stones in a ring of trees, west of the meadow. Something in crimson armour walks here.",
      links = { "test" } },
    { id = "testCave", name = "Cave", art = "cave", x = 82, y = 38,
      about = "East of the meadow. Fallen rocks seal its mouth - a bomb might clear them.",
      links = { "test" } },
    { id = "dungeon", name = "Old Dungeon", art = "fortress", x = 54, y = 88,
      about = "Halls under Willowbrook, older than anyone remembers. Its monsters never stop coming.",
      links = { "village", "lair" } },
    { id = "lair", name = "Gula's Lair", art = "cave", x = 30, y = 84,
      about = "The chamber behind the dungeon's sealed door, where Gula, Demon of Gluttony, was bound.",
      links = { "dungeon" } },
}

places.byId = {}
for _, p in ipairs(places.LIST) do places.byId[p.id] = p end

function places:get(id)
    return self.byId[id]
end

-- a map's name for people ("test" -> "Willow Meadow")
function places:name(id)
    local p = self.byId[id]
    return p and p.name or tostring(id)
end

function places:visited(id)
    return data.visited ~= nil and data.visited[id] == true
end

-- known: been there, or a road from somewhere been leads there
function places:known(id)
    if self:visited(id) then return true end
    local p = self.byId[id]
    if not p then return false end
    for _, other in ipairs(p.links) do
        if self:visited(other) then return true end
    end
    return false
end

function places:countVisited()
    local n = 0
    for _, p in ipairs(self.LIST) do
        if self:visited(p.id) then n = n + 1 end
    end
    return n, #self.LIST
end

-- the hero arrives (src/levels/loadMap.lua): a place seen for the first time
-- goes in the book
function places:visit(id)
    if not self.byId[id] or not data.visited or data.visited[id] then return end
    local first = next(data.visited) == nil -- (where the journey starts isn't news)
    data.visited[id] = true
    if not first then showToast("New place in your Adventure Book: " .. self:name(id), 3) end
end

-- what's written in a map's own file: its Enemies (how many) and Checkpoints
-- (their names), read once
local census = {}
function places:census(id)
    if census[id] then return census[id] end
    local info = { enemies = 0, shrines = {} }
    local ok, map = pcall(function() return love.filesystem.load("maps/" .. id .. ".lua")() end)
    if ok and type(map) == "table" then
        for _, layer in ipairs(map.layers or {}) do
            if layer.name == "Enemies" then info.enemies = #(layer.objects or {}) end
            if layer.name == "Checkpoints" then
                for _, o in ipairs(layer.objects or {}) do
                    table.insert(info.shrines, (o.name and o.name ~= "") and o.name or tostring(o.id))
                end
            end
        end
    end
    census[id] = info
    return info
end

-- monsters a map started with that are gone for good (data.defeated holds them
-- as "map:objectId"), and how many it had
function places:defeated(id)
    local n = 0
    local prefix = id .. ":"
    for key in pairs(data.defeated or {}) do
        if key:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n, self:census(id).enemies
end

-- the shrines a map has, and whether the hero has rested at each
function places:shrines(id)
    local list = {}
    for _, name in ipairs(self:census(id).shrines) do
        table.insert(list, { name = name, touched = data.checkpoints ~= nil and data.checkpoints[id .. ":" .. name] == true })
    end
    return list
end
