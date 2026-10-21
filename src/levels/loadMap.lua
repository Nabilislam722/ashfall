-- whether the hero could stand at x, y: on the map, and in no wall
local function openGround(x, y)
    if x < 0 or y < 0 or x > gameMap.width * gameMap.tilewidth or y > gameMap.height * gameMap.tileheight then return false end
    for _, wall in ipairs(walls) do
        local r = wall.rect
        if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return false end
    end
    return true
end

function loadMap(mapName, destX, destY)
    destroyAll()

    if destX and destY then
        player:setPosition(destX, destY)
    end

    loadedMap = mapName
    gameMap = sti("maps/" .. mapName .. ".lua")
    villageDecor:setMap(gameMap, mapName)
    forestDecor:setMap(gameMap)
    structures:setMap(gameMap)
    wind:clear()

    if gameMap.layers["Walls"] then
        for i, obj in pairs(gameMap.layers["Walls"].objects) do
            spawnWall(obj.x, obj.y, obj.width, obj.height, obj.name, obj.type)
        end
    end

    if gameMap.layers["Enemies"] then
        for i, obj in pairs(gameMap.layers["Enemies"].objects) do
            -- enemies only spawn until they are defeated once
            local key = mapName .. ":" .. obj.id
            if not data.defeated[key] then
                local args = { key = key }
                if obj.properties.form then args.form = obj.properties.form end
                spawnEnemy(obj.x, obj.y, obj.name, args)
            end
        end
    end

    if gameMap.layers["Loot"] then
        for i, obj in pairs(gameMap.layers["Loot"].objects) do
            spawnLoot(obj.x, obj.y, obj.type, false, obj.properties.price)
        end
    end

    if gameMap.layers["Chests"] then
        for i, obj in pairs(gameMap.layers["Chests"].objects) do
            spawnChest(obj.x, obj.y, obj.name, obj.type)
        end
    end

    if gameMap.layers["NPC"] then
        for i, obj in pairs(gameMap.layers["NPC"].objects) do
            -- villagers stand on the bottom-centre of their object box
            spawnNPC(obj.name, obj.x + (obj.width or 16) / 2, obj.y + (obj.height or 16), obj.properties)
        end
    end

    loadSigns(gameMap)
    loadCheckpoints(gameMap, mapName)
    loadSpawners(gameMap, mapName)
    loadLighting(gameMap)

    if gameMap.layers["Transitions"] then
        for i, obj in pairs(gameMap.layers["Transitions"].objects) do
            spawnTransition(obj.x, obj.y, obj.width, obj.height, obj.name, obj.properties.destX, obj.properties.destY, obj.type)
        end
    end

    if gameMap.layers["Triggers"] then
        for i, obj in pairs(gameMap.layers["Triggers"].objects) do
            spawnTrigger(obj.x, obj.y, obj.name)
        end
    end

    if gameMap.layers["Trees"] then
        for i, obj in pairs(gameMap.layers["Trees"].objects) do
            spawnTree(obj.x, obj.y, obj.type, obj.name)
        end
    end

    if gameMap.layers["Water"] then
        for i, obj in pairs(gameMap.layers["Water"].objects) do
            spawnWater(obj.x, obj.y, obj.width, obj.height)
        end
    end

    if gameMap.properties.dark then
        gameMap.dark = gameMap.properties.dark
    else
        gameMap.dark = false
    end

    -- a spot that isn't open ground any more (the map was redrawn since a save
    -- was made there): start at the map's checkpoint instead
    if destX and destY and not openGround(destX, destY) and checkpoints[1] then
        player:setPosition(checkpoints[1].x, checkpoints[1].y + 12)
    end
    loadHighGround(gameMap)

    villageStory:onMapLoaded(gameMap, mapName)
    lairStory:onMapLoaded(gameMap, mapName)
    minimap:build(gameMap, mapName)

end