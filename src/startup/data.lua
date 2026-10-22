function createNewSave(fileNumber)

    -- This represents the save data
    data = {}
    data.saveCount = 0 -- times the game was saved
    data.progress = 0 -- milestone tracker
    data.playerX = 0 -- player's X position
    data.playerY = 0 -- player's Y position
    data.maxHealth = 4 -- maximum number of hearts
    data.money = 0 -- amount of currency
    data.goldEarned = 0 -- all gold picked up on this journey (spending doesn't lower it)
    data.goldExchanged = 0 -- gold traded for HEMI on this journey, as the exchange last reported
    data.lastCheckpoint = nil -- "map:name" of the checkpoint saved at last
    data.keys = 0 -- number of keys
    data.map = "" -- currently loaded map
    data.outfit = 1 -- which cloak is equipped

    if fileNumber == nil then fileNumber = 1 end
    data.fileNumber = fileNumber -- which file are we using

    -- Currently, can equip an item to Z and X
    data.item = {}
    data.item.left = "sword"
    data.item.right = "bow"
    data.item.altL = "fire"
    data.item.altR = "fire"

    -- keep track of certain stackable items
    data.arrowCount = 25
    data.maxArrowCount = 50
    data.bombCount = 10
    data.maxBombCount = 20

    -- table that keeps track of breakables that have been destroyed
    data.breakables = {}

    -- table that keeps track of chests that have been opened
    data.chests = {}

    -- enemies that were defeated ("map:objectId" = true); they don't respawn
    data.defeated = {}

    -- checkpoints the player has touched ("map:name" = true)
    data.checkpoints = {}

    -- monster ears and rare treasures to sell at the Adventurers' Guild (id = count)
    data.bag = {}

    -- story progress for the village of Willowbrook
    data.story = {}
    data.story.villageIntro = false -- saw Rick raiding the village
    data.story.rickDefeated = false -- won the fight in the plaza
    data.story.foodSaved = 0        -- crates still full when Rick gave up
    data.story.heartCharm = false   -- bought Hilda's heart charm
    data.story.rickLosses = 0       -- times Rick knocked the player out
    data.story.masterHinted = false -- a villager pointed the way to Master Juan
    data.story.manaUnlocked = false -- beating Rick opens the Mana Well (veHEMI staking)
    data.story.guildIntro = false   -- Rick's scene at the Adventurers' Guild
    data.story.gulaFrozen = false   -- Rick froze Gula in its lair with his domain
    data.story.rickTalked = false   -- talked to Rick after beating him ("I can't remember anything")
    data.story.rickTalkDay = 0      -- ...on this day; the next day, the village talks about the guild
    data.story.guildHinted = false  -- a villager sent the hero to the Adventurers' Guild

    -- the world's clock (src/levels/worldClock.lua)
    data.day = 1
    data.clock = 0.12 -- the morning of the first day

    -- abilities learned on the adventure
    data.skills = {}
    data.skills.shadowStep = false  -- taught by Master Juan
    data.skills.laserStaff = false  -- Elder Mara's staff, for players Rick keeps beating
end

function saveGame()
    data.saveCount = data.saveCount + 1
    data.playerX = player:getX()
    data.playerY = player:getY()
    data.map = loadedMap

    if data.fileNumber == 1 then
        love.filesystem.write("file1.lua", table.show(data, "data"))
    elseif data.fileNumber == 2 then
        love.filesystem.write("file2.lua", table.show(data, "data"))
    elseif data.fileNumber == 3 then
        love.filesystem.write("file3.lua", table.show(data, "data"))
    end
end
  
function loadGame(fileNumber)
    if fileNumber == 1 then
        if love.filesystem.getInfo("file1.lua") ~= nil then
            local data = love.filesystem.load("file1.lua")
            data()
        else
            startFresh(1)
            return "No data found for save file #1"
        end
    elseif fileNumber == 2 then
        if love.filesystem.getInfo("file2.lua") ~= nil then
            local data = love.filesystem.load("file2.lua")
            data()
        else
            startFresh(2)
            return "No data found for save file #2"
        end
    elseif fileNumber == 3 then
        if love.filesystem.getInfo("file3.lua") ~= nil then
            local data = love.filesystem.load("file3.lua")
            data()
        else
            startFresh(3)
            return "No data found for save file #3"
        end
    end

    --loadMap(data.map, data.playerX, data.playerY)
    player.direction = "down"
    --player.state = 0
    --gamestate = 1
end

function startFresh(fileNumber)
    createNewSave(fileNumber)
    data.map = "test"
    data.playerX = 384 -- Willow Meadow, below the shrine
    data.playerY = 310
    player.state = 0
    player.health = data.maxHealth
    if staff then staff:refill() end
end
