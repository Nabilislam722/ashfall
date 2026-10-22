-- The story of Willowbrook village.
--
-- First visit: a cutscene shows Rick gobbling the village's food while the
-- villagers flee, and Elder Mara asks the player to defend the last crates.
-- Stepping into the plaza starts the boss fight: fences go up around the
-- arena and Rick tries to eat the remaining crates while fighting.
-- Afterwards the villagers trade with the player and Rick joins the village.
--
-- Then: talk to Rick ("I can't remember anything"). The next day (rest at the
-- Sleepy Boar Inn, or wait for morning) the wind picks up and the village is
-- talking about him: any villager points the hero to the Adventurers' Guild,
-- which the minimap highlights, and there Rick remembers who he is.

villageStory = {}
villageStory.active = false
villageStory.crates = {}
villageStory.rick = nil
villageStory.arena = nil
villageStory.barrier = nil
villageStory.barricade = nil
villageStory.fighting = false
villageStory.fightStarted = false
villageStory.displayHealth = 0
villageStory.cheerTimer = 3

local OBJECTIVE = "Stop Rick in the plaza before he eats all the food"
local MASTER_OBJECTIVE = "Find Master Juan by the south-west pond and learn the Shadow Step"
local TALK_RICK = "Talk to Rick"
local REST = "Rest at the Sleepy Boar Inn (east ward) or wait for morning"
local ASK = "Ask the villagers about Rick"
local VISIT_GUILD = "Visit the Adventurers' Guild in the south-east"

-- where Rick's story stands after the fight in the plaza (nil before it, or once
-- he has remembered at the guild)
local function rickQuest()
    local story = data.story
    if not story.rickDefeated or story.guildIntro then return nil end
    if not story.rickTalked then return "talk" end
    if data.day <= story.rickTalkDay then return "rest" end
    if not story.guildHinted then return "ask" end
    return "guild"
end

-- the current village goal, depending on story progress
local function currentObjective()
    local story = data.story
    local quest = rickQuest()
    if quest then
        return ({ talk = TALK_RICK, rest = REST, ask = ASK, guild = VISIT_GUILD })[quest]
    end
    if story.masterHinted and not data.skills.shadowStep then return MASTER_OBJECTIVE end
    if story.villageIntro and not story.rickDefeated then return OBJECTIVE end
    return nil
end

function villageStory:refreshObjective()
    if not self.fighting then objective = currentObjective() end
end

-- what the minimap should point at for the current goal: x, y, kind ("npc" or
-- "guild") in the village, or nil
function villageStory:objectiveTarget()
    local quest = rickQuest()
    local npc
    if quest == "talk" then npc = npcs:find("Rick")
    elseif quest == "rest" then npc = npcs:find("Greta")
    elseif quest == "ask" or quest == "guild" then
        return self.GUILD_HALL.x, self.GUILD_HALL.y, "guild"
    end
    if npc then return npc.x, npc.y, "npc" end
    return nil
end

-- the Adventurers' Guild hall (its footprint in the village: centre and size);
-- the map's Story layer can say where it is (a "guildHall" rectangle)
villageStory.GUILD_HALL = { x = 764, y = 558, w = 160, h = 128 }
-- where the story's people stand, unless the map's Story layer says otherwise:
-- Tom and Lily watching Rick in the plaza, Rick in Hilda's fields after the
-- fight, and Rick at the guild once he remembers
villageStory.SPOTS = { tomWatch = { x = 400, y = 300 }, lilyWatch = { x = 500, y = 336 }, rickFields = { x = 760, y = 384 } }

-- a new day has begun (src/levels/worldClock.lua): returns news for the toast
function villageStory:onNewDay()
    self:refreshObjective()
    if rickQuest() == "ask" then return "the village is talking about Rick" end
    return nil
end
local CHEERS = { "Get him!", "Go, go!", "Save the cheese!", "You can do it!", "Watch out!", "Not the pies!" }

-- a villager's portrait is their own face (their look comes from the map's NPC layer)
local function line(speaker, text)
    local portrait, quad
    if speaker == "Rick" then
        portrait = sprites.enemies.rickPortrait
    elseif speaker == "Hero" then
        portrait = sprites.npc.hero
    else
        local npc = npcs:find(speaker)
        if npc then portrait, quad = npc:portrait() end
    end
    return { speaker = speaker, portrait = portrait, portraitQuad = quad, text = text }
end

----------------------------------------------------------------------- setup

function villageStory:clear()
    if self.rick then
        self.rick:destroy()
        self.rick = nil
    end
    -- crate, barrier and barricade colliders live in `walls` and are
    -- destroyed together with the rest of the map
    self.crates = {}
    self.barrier = nil
    self.barricade = nil
    self.arena = nil
    self.fighting = false
    self.fightStarted = false
    self.active = false
    cam.bias = nil
end

function villageStory:onMapLoaded(map, mapName)
    self:clear()
    self:refreshObjective()

    -- coming back from a lost fight restores the player's zoom
    if self.prevZoom then
        setZoomLevel(self.prevZoom)
        self.prevZoom = nil
    end

    if mapName ~= "village" or not map.layers["Story"] then return end
    self.active = true

    local story = data.story
    local foodObjects = {}
    local rickX, rickY = 448, 312

    for _, obj in ipairs(map.layers["Story"].objects) do
        if obj.type == "arena" then
            self.arena = { x = obj.x, y = obj.y, w = obj.width, h = obj.height }
        elseif obj.type == "rickSpawn" then
            rickX, rickY = obj.x, obj.y
        elseif obj.type == "food" then
            table.insert(foodObjects, obj)
        elseif obj.type == "barricade" then
            self.barricadeRect = { x = obj.x, y = obj.y, w = obj.width, h = obj.height }
        elseif obj.type == "guildHall" then
            self.GUILD_HALL = { x = obj.x + obj.width / 2, y = obj.y + obj.height / 2, w = obj.width, h = obj.height }
        elseif obj.type == "rickGuild" then
            self.RICK_AT_GUILD = { x = obj.x + obj.width / 2, y = obj.y + obj.height / 2 }
        elseif self.SPOTS[obj.type] then
            self.SPOTS[obj.type] = { x = obj.x + obj.width / 2, y = obj.y + obj.height / 2 }
        end
    end

    table.sort(foodObjects, function(a, b) return a.name < b.name end)
    for i, obj in ipairs(foodObjects) do
        -- the intro shows Rick finishing crate #2; after the fight the village restocks
        local eaten = story.villageIntro and not story.rickDefeated and i == 2
        self:spawnCrate(obj.x, obj.y + 10, (obj.properties and obj.properties.variant) or i, eaten)
    end

    if not story.rickDefeated then
        self.rick = spawnRick(rickX, rickY, self.arena)
        self.displayHealth = self.rick.health
        self:spawnBarricade()
        objective = currentObjective()
    end

    self:setupNPCs()

    if respawn.justRevived and story.villageIntro and not story.rickDefeated then
        self.pendingRevivalTalk = true
    end
end

function villageStory:spawnCrate(x, y, variant, eaten)
    local crate = { x = x, y = y, variant = variant, state = eaten and "eaten" or "full", shake = 0, biting = false }
    spawnWall(x - 7, y - 7, 14, 8)

    function crate:setEaten()
        self.state = "eaten"
        self.biting = false
        self.shake = 0.3
    end

    table.insert(self.crates, crate)
    return crate
end

function villageStory:fullCrates()
    local list = {}
    for _, crate in ipairs(self.crates) do
        if crate.state == "full" then table.insert(list, crate) end
    end
    return list
end

function villageStory:spawnBarricade()
    local r = self.barricadeRect
    if not r then return end
    self.barricade = { x = r.x, y = r.y, w = r.w, h = r.h, wall = spawnWall(r.x, r.y, r.w, r.h) }
end

function villageStory:removeBarricade()
    if self.barricade then
        removeWall(self.barricade.wall)
        self.barricade = nil
    end
end

function villageStory:setupNPCs()
    local story = data.story

    for _, npc in ipairs(npcs) do
        npc.onTalk = function(n) self:talk(n) end
        npc.talkLabel = "Talk"
        if npc.role == "trader" then npc.talkLabel = "Trade" end
        if npc.role == "hemi" then npc.talkLabel = "Exchange" end
        if npc.role == "inn" then npc.talkLabel = "Rest" end
        if (npc.role == "baker" or npc.role == "farmer") and story.rickDefeated then npc.talkLabel = "Trade" end
    end

    local tom, lily = npcs:find("Tom"), npcs:find("Lily")
    if not story.villageIntro then
        -- they are in the plaza, watching Rick in horror
        if tom then tom.x, tom.y = self.SPOTS.tomWatch.x, self.SPOTS.tomWatch.y end
        if lily then lily.x, lily.y = self.SPOTS.lilyWatch.x, self.SPOTS.lilyWatch.y end
    elseif not story.rickDefeated then
        for _, npc in ipairs(npcs) do
            if npc.role == "villager" then npc.scared = true end
        end
    else
        local rx, ry = self.SPOTS.rickFields.x, self.SPOTS.rickFields.y
        if story.guildIntro then rx, ry = self.RICK_AT_GUILD.x, self.RICK_AT_GUILD.y end
        local rickNpc = spawnNPC("Rick", rx, ry, { role = "rick", sprite = "rick", scale = 0.42 })
        rickNpc.onTalk = function(n) self:talk(n) end
        rickNpc.talkLabel = "Trade"
    end
end

-- where Rick waits once he has told his story at the Adventurers' Guild
villageStory.RICK_AT_GUILD = { x = 836, y = 640 }

function villageStory:playerInArena(inset)
    local a = self.arena
    if not a then return false end
    local px, py = player:getPosition()
    return px > a.x + inset and px < a.x + a.w - inset and py > a.y + inset and py < a.y + a.h - inset
end

----------------------------------------------------------------------- barrier

function villageStory:raiseBarrier()
    local a = self.arena
    local t = 6
    local barrier = { rise = 0, walls = {}, tiles = {} }

    table.insert(barrier.walls, spawnWall(a.x, a.y - t, a.w, t))
    table.insert(barrier.walls, spawnWall(a.x, a.y + a.h, a.w, t))
    table.insert(barrier.walls, spawnWall(a.x - t, a.y, t, a.h))
    table.insert(barrier.walls, spawnWall(a.x + a.w, a.y, t, a.h))

    local i = 0
    for x = a.x, a.x + a.w - 16, 16 do
        i = i + 1
        local gid = (i % 2 == 1) and 761 or 762
        table.insert(barrier.tiles, { gid = gid, x = x, y = a.y - 12, sortY = a.y })
        table.insert(barrier.tiles, { gid = gid, x = x, y = a.y + a.h - 6, sortY = a.y + a.h + 6 })
    end
    i = 0
    for y = a.y, a.y + a.h - 16, 16 do
        i = i + 1
        local gid = (i % 2 == 1) and 681 or 721
        table.insert(barrier.tiles, { gid = gid, x = a.x - 11, y = y, sortY = y + 16 })
        table.insert(barrier.tiles, { gid = gid, x = a.x + a.w - 5, y = y, sortY = y + 16 })
    end

    self.barrier = barrier
    flux.to(barrier, 0.5, { rise = 1 }):ease("backout")
    shake:start(0.2, 1.5, 0.03)
    dj.play(sounds.items.set, "static", "effect", 1, 0.8)
end

function villageStory:lowerBarrier()
    local barrier = self.barrier
    if not barrier then return end
    for _, wall in ipairs(barrier.walls) do
        removeWall(wall)
    end
    barrier.walls = {}
    flux.to(barrier, 0.4, { rise = 0 }):ease("quadin"):oncomplete(function()
        if self.barrier == barrier then self.barrier = nil end
    end)
end

----------------------------------------------------------------------- cutscenes

function villageStory:playIntro()
    local rick = self.rick
    local tom, lily, elder = npcs:find("Tom"), npcs:find("Lily"), npcs:find("Elder Mara")
    local crate = self.crates[2]

    cutscene:play(function(cs)
        cs:wait(0.5)
        cs:follow(rick, -12)
        cs:wait(1.3)
        cs:say({
            line("Rick", "NOM NOM NOM... Mmmf! Willowbrook bread really is the BEST bread."),
            line("Rick", "And the apples... and the cheese... you know what? I'll just have ALL of it."),
        })

        if tom then tom:setEmote("!", 1.2) end
        if lily then lily:setEmote("!", 1.2) end
        cs:wait(0.4)
        cs:say({
            line("Tom", "He's eating everything! That was our whole harvest!"),
            line("Lily", "Run! Before he decides WE look tasty!"),
        })

        if tom then
            tom.scared = true
            tom:say("Run!", 1.5)
            tom:walkTo(tom.homeX, tom.homeY, 75)
        end
        if lily then
            lily.scared = true
            lily:say("Eek!", 1.5)
            lily:walkTo(lily.homeX, lily.homeY, 75)
        end

        if crate and crate.state == "full" then
            rick:scriptEat(crate)
            cs:waitUntil(function() return crate.state == "eaten" end)
            cs:wait(0.3)
            cs:say({ line("Rick", "*BURP*  ...Ahh. Right. NEXT crate!") })
            cs:waitUntil(function() return rick.state == "feast" end)
        end

        cs:focusPlayer()
        cs:wait(0.7)

        if elder then
            elder:setEmote("!", 1.2)
            cs:walk(elder, player:getX() - 22, player:getY() + 18, 65)
            elder:face(player:getX())
        end

        cs:say({
            line("Elder Mara", "Traveler! Thank the stars. I'm Mara, elder of Willowbrook."),
            line("Elder Mara", "That's Rick. He rolled in at dawn and hasn't stopped eating since."),
            line("Elder Mara", "Those crates in the plaza are all the food we have left for winter. If he eats them, we starve."),
            line("Elder Mara", "Please, defend our village! Drive Rick off before the last crate is gone."),
            line("Elder Mara", "Pip at the market stall can trade you supplies. Step into the plaza when you're ready."),
        })

        if elder then elder:walkTo(elder.homeX, elder.homeY, 45) end
    end, function()
        data.story.villageIntro = true
        objective = OBJECTIVE
        showToast("Press E near villagers to talk and trade", 4)
    end)
end

function villageStory:playRevival()
    self.pendingRevivalTalk = false
    local elder = npcs:find("Elder Mara")
    local story = data.story
    story.rickLosses = story.rickLosses + 1
    local firstLoss = story.rickLosses == 1 and not data.skills.shadowStep
    local giveStaff = story.rickLosses >= 2 and not data.skills.laserStaff

    cutscene:play(function(cs)
        cs:wait(0.4)
        if elder then
            cs:walk(elder, player:getX() - 20, player:getY() + 16, 70)
            elder:face(player:getX())
        end
        if giveStaff then
            cs:say({
                line("Elder Mara", "Twice now that glutton has flattened you. Stubborn, aren't you? I like that."),
                line("Elder Mara", "Here. Take my old Storm Staff. I haven't needed it since I was young."),
                line("Elder Mara", "Hold it up and it drinks mana from the land around you. Let go, and it fires all of it at once."),
                line("Elder Mara", "The longer you gather, the harder it hits. Even Rick can't chew through that!"),
            })
        elseif firstLoss then
            cs:say({
                line("Elder Mara", "Easy there, you took quite a beating! We dragged you back to the gate."),
                line("Elder Mara", "Courage alone won't beat that glutton. You need to be quicker than his belly flops."),
                line("Elder Mara", "Go and see Master Juan. He meditates by the pond in the south-west of the village."),
                line("Elder Mara", "Ask him about the Shadow Step. If anyone can teach you to slip past Rick, it's him."),
            })
            story.masterHinted = true
            objective = currentObjective()
            showToast("Master Juan is marked on your map", 3.5)
        else
            cs:say({
                line("Elder Mara", "Easy there, you took quite a beating! We dragged you back to the gate."),
                line("Elder Mara", "Roll or Shadow Step through his shockwaves, and strike while he's busy stuffing his face."),
                line("Elder Mara", "Pip can patch you up with supplies. Willowbrook is counting on you!"),
            })
        end
        if elder then elder:walkTo(elder.homeX, elder.homeY, 45) end
    end, function()
        if giveStaff then
            data.skills.laserStaff = true
            data.item.right = "staff"
            player:gotItem(sprites.items.staff)
            dj.play(sounds.items.chest, "static", "effect")
            showToast("Storm Staff!  Hold right-click to charge, let go to call down lightning", 5)
        end
    end)
end

function villageStory:teachShadowStep(juan)
    local story = data.story
    local opener
    if story.rickDefeated and story.rickLosses == 0 then
        opener = line("Master Juan", "You beat the glutton without anyone's help, and still you found your way to me. Impressive.")
    elseif story.masterHinted then
        opener = line("Master Juan", "Mara sent you. I watched Rick flatten you from here. Painful to see.")
    else
        opener = line("Master Juan", "Few find this quiet corner by chance. Sit a moment, traveler.")
    end

    dialogue:start({
        opener,
        line("Master Juan", "Close your eyes. Feel the shadow under your feet... and step into it."),
        line("Master Juan", "The Shadow Step carries you a short way in an instant. Claws, crumbs and shockwaves pass right through you."),
        line("Master Juan", "Walls will still stop you, and it needs a breath to recharge. Press Q, and go."),
    }, function()
        data.skills.shadowStep = true
        player.shadowCooldown = 0
        player:gotItem(sprites.items.shadowStep)
        dj.play(sounds.items.chest, "static", "effect")
        showToast("Learned Shadow Step!  Press Q to dash through danger", 4.5)
        objective = currentObjective()
    end)
end

-- the two sides of the VS banner
local function versusCards()
    local hero = {
        image = sprites.playerSheet,
        quad = love.graphics.newQuad(0, 0, 19, 21, sprites.playerSheet:getDimensions()),
        name = "HERO",
        title = "Defender of Willowbrook",
        color = {0.09, 0.2, 0.38},
        glow = {0.35, 0.75, 1},
    }
    local rick = {
        image = sprites.enemies.rickPortrait,
        name = "RICK",
        title = "The Bottomless Stomach",
        color = {0.42, 0.07, 0.05},
        glow = {1, 0.5, 0.2},
    }
    return hero, rick
end

function villageStory:startFight()
    self.fightStarted = true
    local rick = self.rick

    cutscene:play(function(cs)
        cs:follow(rick, -12)
        rick:say("!", {1, 0.4, 0.3}, true)
        cs:wait(0.7)
        cs:say({
            line("Rick", "Hm? Another hungry mouth? Forget it. These snacks are MINE!"),
            line("Rick", "You want food? Come and take it from me!"),
        })
        self:raiseBarrier()
        cs:wait(0.6)
        cs:focusPlayer()
        cs:wait(0.3)
        cs:versus(versusCards())
    end, function()
        self.fighting = true
        self.prevZoom = zoomTarget
        setZoomLevel(0.75)
        rick:beginFight()
        objective = OBJECTIVE
        showToast("Hit Rick while he's eating to make him choke!", 3.5)
    end)
end

function villageStory:onRickDefeated()
    self.fighting = false
    objective = nil
    local rick = self.rick
    local elder = npcs:find("Elder Mara")
    local saved = #self:fullCrates()
    local coins = 20 + saved * 10

    local savedLine
    if saved == #self.crates - 1 then
        savedLine = "And not a single crate lost after you arrived! The winter stores are safe."
    elseif saved > 0 then
        savedLine = "You saved " .. saved .. (saved == 1 and " crate" or " crates") .. " of food. That will see us through the winter."
    else
        savedLine = "The crates are empty... but Hilda's fields will grow again, now that you've stopped him."
    end

    cutscene:play(function(cs)
        cs:wait(1.4)
        cs:follow(rick, -12)
        self:lowerBarrier()
        cs:wait(0.6)
        cs:say({
            line("Rick", "Oof... okay... OKAY! I give up! No more!"),
            line("Rick", "I was just... so... hungry. Your food smelled AMAZING."),
        })

        if elder then
            cs:walk(elder, rick.x - 28, rick.y + 8, 70)
            elder:face(rick.x)
        end

        cs:say({
            line("Elder Mara", "Hungry or not, you can't take everything, Rick."),
            line("Elder Mara", "But nobody in Willowbrook goes hungry either. Help Hilda bring in the harvest, and you'll always have a seat at our table."),
            line("Rick", "...Really? Deal! Sorry, everyone. I'll start with a salad."),
        })

        flux.to(rick, 1.2, { size = 0.5 }):ease("quadinout")
        cs:wait(1.3)

        for _, npc in ipairs(npcs) do
            if npc.role ~= "elder" then
                npc.scared = false
                npc:setEmote("heart", 2)
            end
        end

        cs:focusPlayer()
        if elder then
            cs:walk(elder, player:getX() - 22, player:getY() + 14, 70)
            elder:face(player:getX())
        end
        cs:say({
            line("Elder Mara", "As for you, hero: you saved Willowbrook. " .. savedLine),
            line("Elder Mara", "Please, take this heart charm, and a little something from the village purse."),
            line("Elder Mara", "Mari's ovens will be warm again soon, and the south road to the old dungeon is open."),
            line("Elder Mara", "Oh, and Nova at the Hemi Exchange stall will trade your gold for real HEMI tokens."),
            line("Elder Mara", "With Rick tamed, the Mana Well by the north gate is awake again. Vera binds HEMI into veHEMI there."),
            line("Elder Mara", data.skills.laserStaff
                and "Stake more HEMI with her and your mana capacity grows. Go and see her!"
                or "Take my old Storm Staff: it drinks mana from the land. Stake more HEMI with Vera and your mana capacity grows."),
            line("Elder Mara", "And Rick... he looks so dazed. Go and talk to him, would you?"),
        })
        if elder then elder:walkTo(elder.homeX, elder.homeY, 45) end
    end, function()
        data.story.rickDefeated = true
        data.story.foodSaved = saved
        objective = currentObjective()
        data.maxHealth = data.maxHealth + 1
        player.health = data.maxHealth
        data.money = data.money + coins
        data.goldEarned = data.goldEarned + coins
        data.story.manaUnlocked = true
        local newStaff = not data.skills.laserStaff
        data.skills.laserStaff = true
        player:gotItem(sprites.items.container)
        dj.play(sounds.items.chest, "static", "effect")
        showToast("Max hearts +1   +" .. coins .. " gold   Mana Well unlocked!" .. (newStaff and "   Storm Staff (equip with Tab)" or ""), 5)

        if self.prevZoom then
            setZoomLevel(self.prevZoom)
            self.prevZoom = nil
        end
        self:removeBarricade()

        -- the defeated boss becomes a (much smaller) villager
        local rx, ry = rick.x, rick.y
        rick:destroy()
        self.rick = nil
        local rickNpc = spawnNPC("Rick", rx, ry, { role = "rick", sprite = "rick", scale = 0.42 })
        rickNpc.onTalk = function(n) self:talk(n) end
        rickNpc.talkLabel = "Trade"
        rickNpc:walkTo(self.SPOTS.rickFields.x, self.SPOTS.rickFields.y, 40)

        for _, npc in ipairs(npcs) do
            if npc.role == "baker" or npc.role == "farmer" then npc.talkLabel = "Trade" end
        end
    end)
end

----------------------------------------------------------------------- trading

local function healOffer(name, desc, amount, cost, foodIndex)
    return {
        name = name,
        desc = desc,
        icon = sprites.items.food,
        iconQuad = sprites.items.foodQuads[foodIndex],
        cost = cost,
        canBuy = function()
            if player.health >= data.maxHealth then return false, "You're already at full health." end
            return true
        end,
        blockedLabel = "Full health",
        give = function() player.health = math.min(data.maxHealth, player.health + amount) end,
        thanks = "Delicious! You feel better.",
    }
end

local function arrowOffer(name, desc, amount, cost)
    return {
        name = name,
        desc = desc,
        icon = sprites.items.arrow,
        iconRot = math.pi / -4,
        cost = cost,
        canBuy = function()
            if data.arrowCount >= data.maxArrowCount then return false, "Your quiver is already full." end
            return true
        end,
        blockedLabel = "Quiver full",
        give = function() data.arrowCount = math.min(data.maxArrowCount, data.arrowCount + amount) end,
    }
end

local function bombOffer(name, desc, amount, cost)
    return {
        name = name,
        desc = desc,
        icon = sprites.items.bomb,
        cost = cost,
        canBuy = function()
            if data.bombCount >= data.maxBombCount then return false, "You can't carry any more bombs." end
            return true
        end,
        blockedLabel = "Bag full",
        give = function() data.bombCount = math.min(data.maxBombCount, data.bombCount + amount) end,
    }
end

function villageStory:pipOffers()
    return {
        arrowOffer("Arrows x10", "A bundle of sturdy arrows for your bow.", 10, { coins = 5 }),
        bombOffer("Bombs x3", "Handle with care. Great for big targets.", 3, { coins = 9 }),
        healOffer("Apple", "Crisp and sweet. Restores 1 heart.", 1, { coins = 3 }, 2),
        bombOffer("Swap 6 arrows for a bomb", "Pip loves a good trade.", 1, { arrows = 6 }),
        arrowOffer("Swap a bomb for 5 arrows", "Pip loves a good trade.", 5, { bombs = 1 }),
    }
end

function villageStory:bakerOffers()
    return {
        healOffer("Fresh bread", "Still warm from the oven. Restores 2 hearts.", 2, { coins = 5 }, 1),
        healOffer("Roast drumstick", "Mari's speciality. Restores 3 hearts.", 3, { coins = 8 }, 3),
        healOffer("Honey cheese", "Rick's favourite. Restores all hearts.", 99, { coins = 12 }, 4),
    }
end

function villageStory:hildaOffers()
    return {
        healOffer("Apple", "Picked this morning. Restores 1 heart.", 1, { coins = 2 }, 2),
        {
            name = "Heart charm",
            desc = "Hilda's lucky charm, woven from harvest straw. +1 max heart.",
            icon = sprites.items.container,
            cost = { coins = 40 },
            soldOut = function() return data.story.heartCharm end,
            give = function()
                data.story.heartCharm = true
                data.maxHealth = data.maxHealth + 1
                player.health = data.maxHealth
            end,
            thanks = "May it keep you safe out there!",
        },
        healOffer("Swap 4 arrows for an apple", "Hilda uses them to scare crows.", 1, { arrows = 4 }, 2),
    }
end

function villageStory:rickOffers()
    return {
        healOffer("Leftover drumstick", "Only a little nibbled. Restores 2 hearts.", 2, { bombs = 1 }, 3),
        healOffer("Emergency cheese", "From Rick's secret stash. Restores all hearts.", 99, { arrows = 8 }, 4),
        bombOffer("Bomb he found", "Rick found it in a crate. He did not try to eat it. Probably.", 1, { coins = 4 }),
    }
end

function villageStory:guildOffers()
    local offers = {
        {
            name = function()
                local ears, rares = mobLoot:totals()
                return "Sell everything  (" .. (ears + rares) .. ")"
            end,
            desc = "Hand over every ear and treasure in your bag.",
            icon = sprites.items.mobLoot,
            iconQuad = mobLoot:quad("skeletonEar"),
            cost = {},
            priceLabel = function() return "+" .. mobLoot:value() .. " gold" end,
            canBuy = function()
                if mobLoot:value() <= 0 then return false, "Your bag is empty. Monsters roam the dungeon south of the village!" end
                return true
            end,
            blockedLabel = "empty bag",
            give = function()
                local total = 0
                for _, id in ipairs(mobLoot.ORDER) do
                    local _, gold = mobLoot:sell(id)
                    total = total + gold
                end
                return total
            end,
            thanks = function(gold) return "Fine work, adventurer! Here's " .. gold .. " gold." end,
        },
    }
    for _, id in ipairs(mobLoot.ORDER) do
        local item = mobLoot.ITEMS[id]
        table.insert(offers, {
            name = function() return item.name .. "  x" .. mobLoot:count(id) end,
            desc = item.desc .. "  The guild pays " .. item.price .. " gold each.",
            icon = sprites.items.mobLoot,
            iconQuad = mobLoot:quad(id),
            cost = {},
            priceLabel = function() return "+" .. mobLoot:count(id) * item.price .. " gold" end,
            canBuy = function()
                if mobLoot:count(id) <= 0 then return false, "You don't have any " .. item.name .. "s yet." end
                return true
            end,
            blockedLabel = item.price .. "g each",
            give = function()
                local _, gold = mobLoot:sell(id)
                return gold
            end,
            thanks = function(gold) return "Sold for " .. gold .. " gold!" end,
        })
    end
    return offers
end

function villageStory:openGuild()
    shop:open("Adventurers' Guild", "Mira", self:guildOffers(),
        "Monster ears are proof of a hunt, and the guild pays for every one. Rare finds are worth a fortune!")
end

-- the first visit to the guild: Rick tells the hero who he really is
function villageStory:playGuildIntro(mira)
    local rick = npcs:find("Rick")
    if not rick then
        rick = spawnNPC("Rick", player:getX() + 60, player:getY() + 10, { role = "rick", sprite = "rick", scale = 0.42 })
        rick.onTalk = function(n) self:talk(n) end
        rick.talkLabel = "Trade"
    end

    cutscene:play(function(cs)
        cs:say({ line("Mira", "Welcome to the Adventurers' Guild! Oh, and look who's here...") })
        rick:setEmote("!", 1.2)
        cs:walk(rick, player:getX() + 22, player:getY() + 6, 75)
        rick:face(player:getX())
        cs:wait(0.3)
        cs:say({
            line("Rick", "This hall... the guild! It's all coming back to me!"),
            line("Hero", "Don't tell me you still want to eat more after that?"),
            line("Rick", "Don't be rude! I was cursed by a boss in the dungeon."),
            line("Rick", "I'm a well-known adventurer, you know."),
            line("Mira", "It's true! Rick was our top adventurer, until the dungeon's master cursed him with an endless hunger."),
            line("Mira", "Ever since, the dungeon south of the village spawns monsters day and night."),
            line("Mira", "Bring us their ears as proof of your hunts and the guild pays in gold. About one monster in a hundred carries something rare: those are worth a fortune!"),
            line("Rick", "Get strong enough to break my curse, and I'll buy you the biggest feast in Willowbrook. ...I'll only eat half of it."),
        })
    end, function()
        data.story.guildIntro = true
        self:refreshObjective()
        rick.homeX, rick.homeY = self.RICK_AT_GUILD.x, self.RICK_AT_GUILD.y
        rick:walkTo(self.RICK_AT_GUILD.x, self.RICK_AT_GUILD.y, 40)
        showToast("Sell monster ears at the Adventurers' Guild", 3.5)
        self:openGuild()
    end)
end

----------------------------------------------------------------------- Rick's memory

-- after the fight: Rick can't remember who he is
function villageStory:talkToRick(rick)
    rick:face(player:getX())
    cutscene:play(function(cs)
        cs:say({
            line("Hero", "Rick? Are you alright? What happened to you?"),
            line("Rick", "Rick... yes, that's my name. But everything else..."),
            line("Rick", "I can't remember anything."),
            line("Rick", "Only a cold, dark place... and a hunger that wouldn't stop."),
            line("Rick", "My head is spinning. Let me rest. Maybe tomorrow it'll come back to me."),
        })
    end, function()
        data.story.rickTalked = true
        data.story.rickTalkDay = data.day
        self:refreshObjective()
        showToast("Rest at the Sleepy Boar Inn in the east ward to skip to morning", 4)
    end)
end

-- the next day, any villager can point the hero to the guild
local GOSSIP = {
    ["Elder Mara"] = { "Rick? I remember now... he came through Willowbrook years ago, a famous adventurer.",
        "Mira at the Adventurers' Guild keeps the records. Ask her!" },
    Tom = { "My dad says Rick used to be the best adventurer around!", "Ask at the Adventurers' Guild in the south-east. They'll know!" },
    Lily = { "I saw an old poster of Rick at the Adventurers' Guild!", "It's the big hall by the trees in the south-east." },
    Pip = { "Rick? He used to buy arrows by the barrel, back when he worked for the Adventurers' Guild.",
        "Go and ask Mira there, in the south-east." },
    Mari = { "Rick used to bring the guild's hunters here for bread after every hunt.", "The Adventurers' Guild, south-east. Mira will remember him." },
    Hilda = { "Strange wind today... and strange talk. They say Rick was the guild's top adventurer.",
        "The Adventurers' Guild is in the south-east, past the fountain." },
    Greta = { "Rick? He used to stay here after every hunt for the Adventurers' Guild. Ate the whole pantry, mind you.",
        "Mira at the guild, south-east of the plaza, knows his story." },
    Kip = { "Rick's a real adventurer! Mira at the guild has his name on the wall!", "The Adventurers' Guild! South-east! Go go go!" },
    Nova = { "Rick? There's an old guild contract with his name on it. The Adventurers' Guild, south-east." },
    Vera = { "The well remembers Rick's mana... he was an adventurer of the guild.", "Seek Mira at the Adventurers' Guild in the south-east." },
    ["Master Juan"] = { "Rick. I sparred with him once, long ago. A guild adventurer, and a fine one.",
        "Mira at the Adventurers' Guild can tell you more." },
}

function villageStory:gossip(npc)
    local said = GOSSIP[npc.name] or { "Rick? People say he was an adventurer.", "Ask at the Adventurers' Guild in the south-east." }
    local lines = {}
    for _, text in ipairs(said) do table.insert(lines, line(npc.name, text)) end
    npc:face(player:getX())
    dialogue:start(lines, function()
        data.story.guildHinted = true
        self:refreshObjective()
        showToast("The Adventurers' Guild is marked on your map", 3.5)
    end)
end

----------------------------------------------------------------------- the inn

function villageStory:restOffers()
    return {
        {
            name = "A night's rest",
            desc = "Sleep until morning. A new day begins, and your hearts are restored.",
            icon = sprites.items.heart,
            cost = {},
            priceLabel = "Free",
            give = function()
                shop:close()
                self:rest()
            end,
            thanks = "Sleep well!",
        },
    }
end

-- sleep at the inn: the eyes close, and open on a new morning
function villageStory:rest()
    cutscene:play(function(cs)
        cs:wait(0.2)
        domainFx:setEyes(1, 1.1)
        cs:waitUntil(function() return not domainFx:blinking() end)
        cs:wait(0.8)
        worldClock:sleep()
        player.health = data.maxHealth
        cs:wait(0.4)
        domainFx:setEyes(0, 1.3)
        cs:waitUntil(function() return not domainFx:blinking() end)
    end)
end

----------------------------------------------------------------------- talking

function villageStory:talk(npc)
    local s = data.story
    local won = s.rickDefeated
    local role = npc.role

    -- the day after Rick lost his memory, everyone is talking about him
    if rickQuest() == "ask" and role ~= "rick" and role ~= "guild" and role ~= "inn" then
        self:gossip(npc)
        return
    end

    if role == "elder" then
        if won then
            dialogue:start({
                line("Elder Mara", "Willowbrook is in your debt. Rick has been working in Hilda's fields all day."),
                line("Elder Mara", "The south road leads to the old dungeon. Be careful down there."),
            })
        else
            dialogue:start({
                line("Elder Mara", "Rick is still gorging himself in the plaza. Please, stop him before the last crates are gone!"),
                line("Elder Mara", "If you need supplies, Pip trades at the market stall to the west."),
            })
        end
    elseif role == "trader" then
        local greeting = won and "Business is booming again! Have a look." or "Rick ate my lunch, but he can't eat arrows! Take a look."
        shop:open("Pip's Goods", "Pip", self:pipOffers(), greeting)
    elseif role == "baker" then
        if won then
            shop:open("Mari's Bakery", "Mari", self:bakerOffers(), "The ovens are warm again! Everything's fresh.")
        else
            dialogue:start({
                line("Mari", "My ovens are cold... Rick ate every last loaf, and then the flour sacks."),
                line("Mari", "Stop him, and I'll bake you something special!"),
            })
        end
    elseif role == "farmer" then
        if won then
            shop:open("Hilda's Farm Stand", "Hilda", self:hildaOffers(), "Rick's a natural at weeding, who knew? Fresh from the fields:")
        else
            dialogue:start({
                line("Hilda", "That glutton trampled my turnips and ate my seed corn!"),
                line("Hilda", "Careful when he jumps. The ground shakes when he lands. Roll right through the shockwave!"),
            })
        end
    elseif role == "hemi" then
        hemiExchange:open()
    elseif role == "guild" then
        if not won then
            dialogue:start({
                line("Mira", "Welcome to the Adventurers' Guild... or it would be, if anyone dared to work while that glutton runs riot in the plaza."),
                line("Mira", "Deal with him first, then come back and we'll talk business."),
            })
        elseif not s.rickTalked then
            dialogue:start({
                line("Mira", "So you're the one who stopped that glutton! Though he looked completely lost afterwards."),
                line("Mira", "Has anyone even talked to him?"),
            })
        elseif not s.guildIntro then
            self:playGuildIntro(npc)
        else
            self:openGuild()
        end
    elseif role == "manaWell" then
        if s.manaUnlocked or won then
            manaWell:open()
        else
            dialogue:start({
                line("Vera", "Shh... the Mana Well sleeps while Rick runs riot in the plaza."),
                line("Vera", "Stop him, and you can stake HEMI here. The more HEMI you stake, the bigger your mana capacity."),
            })
        end
    elseif role == "master" then
        if data.skills.shadowStep then
            dialogue:start({
                line("Master Juan", "Shadow Step slips you through enemies and their attacks, but never through walls."),
                line("Master Juan", "Step, strike, step away. Patience wins more fights than strength."),
            })
        elseif s.rickLosses > 0 or s.rickDefeated or s.masterHinted then
            self:teachShadowStep(npc)
        else
            dialogue:start({
                line("Master Juan", "Hm. A traveler. That glutton is still gorging himself in the plaza."),
                line("Master Juan", "Face him first. If he knocks you down, come back to me and I'll teach you something."),
            })
        end
    elseif role == "rick" then
        local quest = rickQuest()
        if quest == "talk" then
            self:talkToRick(npc)
        elseif quest == "rest" then
            dialogue:start({ line("Rick", "Let me rest a while... maybe tomorrow it'll come back to me.") })
        elseif quest == "ask" or quest == "guild" then
            dialogue:start({ line("Rick", "Something about the Adventurers' Guild keeps nagging at me...") })
        else
            shop:open("Rick's Snack Swap", "Rick", self:rickOffers(), "Sorry about all that. I get a little hangry. Want to trade snacks?")
        end
    elseif role == "inn" then
        local greeting = worldClock:isNight() and "Late night, traveler? We've a warm bed for you."
            or "Welcome to the Sleepy Boar! Rest here and you'll wake to a new morning."
        shop:open("Sleepy Boar Inn", "Greta", self:restOffers(), greeting)
    elseif npc.name == "Tom" then
        if won then
            dialogue:start({ line("Tom", "Rick's actually a nice guy once he's had a salad.") })
        else
            dialogue:start({
                line("Tom", "Did you see how fast he eats? I blinked and a whole pie was gone."),
                line("Tom", "If you hit him while he's chewing, I bet he'd choke on it!"),
            })
        end
    elseif npc.name == "Lily" then
        if won then
            dialogue:start({ line("Lily", "We're throwing a feast tonight! Rick promised to only take ONE plate.") })
        else
            dialogue:start({
                line("Lily", "He spits food when he's angry. Gross!"),
                line("Lily", "And when he gets really mad he charges. Make him run into the fence!"),
            })
        end
    elseif npc.name == "Kip" then
        if not won then
            dialogue:start({ line("Kip", "Is the big hungry man gone yet? I'm hiding till he's gone.") })
        elseif s.gulaFrozen then
            dialogue:start({ line("Kip", "The wind stopped! Did you do that?") })
        elseif data.day >= 2 then
            dialogue:start({ line("Kip", "Woooah, the wind! Look at the windmill go!") })
        else
            dialogue:start({ line("Kip", "When I grow up I'm gonna be an adventurer, just like you!") })
        end
    else
        dialogue:start({ line(npc.name, "Hello there!") })
    end
end

----------------------------------------------------------------------- update

function villageStory:update(dt)
    if not self.active or pause.active then return end

    if self.rick then self.rick:update(dt) end

    -- while his story goes on, Rick wants to talk; afterwards he trades snacks
    local rickNpc = npcs:find("Rick")
    if rickNpc and rickNpc.role == "rick" then rickNpc.talkLabel = rickQuest() and "Talk" or "Trade" end

    for _, crate in ipairs(self.crates) do
        if crate.shake > 0 then crate.shake = crate.shake - dt end
    end

    local story = data.story
    if not cutscene.active and curtain.state == 0 and not respawn.pending and not dialogue.active and not shop.active then
        if not story.villageIntro then
            self:playIntro()
        elseif self.pendingRevivalTalk then
            self:playRevival()
        elseif self.rick and not self.fightStarted and self:playerInArena(20) then
            self:startFight()
        end
    end

    if self.rick then
        self.displayHealth = self.displayHealth + (self.rick.health - self.displayHealth) * math.min(1, dt * 6)
    end

    -- keep Rick in frame during the fight
    if self.fighting and self.rick then
        cam.bias = cam.bias or {}
        cam.bias.x, cam.bias.y, cam.bias.weight = self.rick.x, self.rick.y - 16, 0.35
    else
        cam.bias = nil
    end

    if self.fighting then
        self.cheerTimer = self.cheerTimer - dt
        if self.cheerTimer <= 0 then
            self.cheerTimer = 2.5 + math.random() * 3
            local candidates = {}
            for _, npc in ipairs(npcs) do
                if not npc.hidden and distanceBetween(npc.x, npc.y, player:getX(), player:getY()) < 220 then
                    table.insert(candidates, npc)
                end
            end
            if #candidates > 0 then
                candidates[math.random(1, #candidates)]:say(CHEERS[math.random(1, #CHEERS)], 1.6)
            end
        end
    end
end

----------------------------------------------------------------------- drawing

local function drawCrate(crate)
    local jx = 0
    if crate.shake > 0 or crate.biting then jx = (math.random() * 2 - 1) * 0.8 end
    local frame = crate.state == "full" and crate.variant or 5
    setWhite()
    love.graphics.draw(sprites.village.foodCrates, sprites.village.crateQuads[frame], crate.x + jx, crate.y + 1, 0, 1, 1, 8, 22)
end

local function drawRick(rick)
    rick:draw()
end

local function drawFenceTile(tile)
    local barrier = villageStory.barrier
    local rise = barrier and barrier.rise or 1
    if rise <= 0.01 then return end
    love.graphics.setColor(1, 1, 1, math.min(1, rise))
    love.graphics.draw(sprites.village.tiles, getVillageTileQuad(tile.gid), tile.x, tile.y + (1 - rise) * 10)
    setWhite()
end

local function drawBarricade(b)
    for i = 0, 2 do
        local gid = (i % 2 == 0) and 761 or 762
        love.graphics.draw(sprites.village.tiles, getVillageTileQuad(gid), b.x - 4 + i * 16, b.y - 10)
    end
    love.graphics.draw(sprites.village.foodCrates, sprites.village.crateQuads[5], b.x + 6, b.y + 12, 0, 1, 1, 8, 22)
    love.graphics.draw(sprites.village.foodCrates, sprites.village.crateQuads[5], b.x + b.w - 6, b.y + 12, 0, 1, 1, 8, 22)
end

function villageStory:drawGround()
    if not self.active then return end
    if self.rick then self.rick:drawGround() end
end

function villageStory:collect(items)
    if not self.active then return end
    for _, crate in ipairs(self.crates) do
        table.insert(items, { y = crate.y, draw = drawCrate, arg = crate })
    end
    if self.rick then
        table.insert(items, { y = self.rick.y + 4, draw = drawRick, arg = self.rick })
    end
    if self.barrier then
        for _, tile in ipairs(self.barrier.tiles) do
            table.insert(items, { y = tile.sortY, draw = drawFenceTile, arg = tile })
        end
    end
    if self.barricade then
        table.insert(items, { y = self.barricade.y + self.barricade.h, draw = drawBarricade, arg = self.barricade })
    end
end

function villageStory:drawAir()
    if not self.active then return end
    if self.rick then self.rick:drawAir() end
end

function villageStory:drawHUD()
    if not self.active or not self.fighting or not self.rick then return end

    local w = love.graphics.getWidth()
    local barW = 120 * scale
    local barH = 4 * scale
    local x = (w - barW) / 2
    local y = 9 * scale
    local border = math.max(2, math.floor(scale * 0.6))

    love.graphics.setFont(fonts.small)
    local title = "RICK, THE BOTTOMLESS STOMACH"
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.printf(title, x + scale * 0.4, y - fonts.small:getHeight() - scale * 0.6, barW, "center")
    love.graphics.setColor(1, 0.86, 0.6, 1)
    love.graphics.printf(title, x, y - fonts.small:getHeight() - scale, barW, "center")

    love.graphics.setColor(0.05, 0.04, 0.06, 0.9)
    love.graphics.rectangle("fill", x - border, y - border, barW + border * 2, barH + border * 2, scale * 0.5, scale * 0.5)
    local ratio = math.max(0, self.displayHealth / self.rick.maxHealth)
    local trueRatio = math.max(0, self.rick.health / self.rick.maxHealth)
    love.graphics.setColor(1, 0.9, 0.7, 0.8)
    love.graphics.rectangle("fill", x, y, barW * math.max(ratio, trueRatio), barH)
    love.graphics.setColor(0.86, 0.22, 0.2, 1)
    love.graphics.rectangle("fill", x, y, barW * math.min(ratio, trueRatio), barH)
    love.graphics.setColor(1, 0.5, 0.42, 1)
    love.graphics.rectangle("fill", x, y, barW * math.min(ratio, trueRatio), barH * 0.35)

    -- food left: one crate icon per crate, to the right of the bar
    local iconScale = scale * 0.4
    local gap = 14 * iconScale
    local startX = x + barW + border + 10 * iconScale
    local iconY = y + barH / 2 - 2 * iconScale
    for i, crate in ipairs(self.crates) do
        local frame = crate.state == "full" and crate.variant or 5
        if crate.biting then
            love.graphics.setColor(1, 0.6, 0.5, 0.6 + math.sin(love.timer.getTime() * 12) * 0.4)
        elseif crate.state == "full" then
            setWhite()
        else
            love.graphics.setColor(1, 1, 1, 0.45)
        end
        love.graphics.draw(sprites.village.foodCrates, sprites.village.crateQuads[frame], startX + (i - 1) * gap, iconY, 0, iconScale, iconScale, 8, 12)
    end
    setWhite()
end
