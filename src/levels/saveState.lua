-- Saving and loading a journey.
--
-- A save is a small JSON snapshot of `data` plus where the player stood. It is
-- written to save.json on this device every time, and to the player's slot in
-- the AshfallSaves contract when a wallet is connected (web/bridge.js
-- "save"). Loading validates every field, because a save can come from a file
-- or a chain that anyone can write to: unknown or out-of-range values fall back
-- to defaults instead of breaking the game.

local json = require("src/utilities/json")

saveState = {}
saveState.FILE = "save.json"
saveState.VERSION = 1

local ITEMS = { sword = true, bow = true, boomerang = true, bomb = true, grapple = true, fire = true, staff = true }
local STORY = {
    villageIntro = "bool", rickDefeated = "bool", foodSaved = "int", heartCharm = "bool",
    rickLosses = "int", masterHinted = "bool", manaUnlocked = "bool", guildIntro = "bool", gulaFrozen = "bool",
    rickTalked = "bool", rickTalkDay = "day", guildHinted = "bool",
}
local SKILLS = { shadowStep = true, laserStaff = true }
local MAX_LIST = 400

local function int(value, low, high, default)
    local n = tonumber(value)
    if not n or n ~= n then return default end
    return math.max(low, math.min(high, math.floor(n)))
end

local function setToList(set)
    local list = {}
    for key, value in pairs(set or {}) do
        if value and type(key) == "string" then table.insert(list, key) end
    end
    table.sort(list)
    return list
end

local function listToSet(list)
    local set = {}
    if type(list) ~= "table" then return set end
    for i, key in ipairs(list) do
        if i > MAX_LIST then break end
        if type(key) == "string" and #key <= 80 then set[key] = true end
    end
    return set
end

-- the current game as a plain table
function saveState:snapshot(mapName, x, y)
    local story, skills = {}, {}
    for key in pairs(STORY) do story[key] = data.story[key] end
    for key in pairs(SKILLS) do skills[key] = data.skills[key] == true end
    return {
        v = self.VERSION,
        map = mapName,
        x = math.floor(x + 0.5),
        y = math.floor(y + 0.5),
        cp = data.lastCheckpoint,
        hp = player.health,
        maxHp = data.maxHealth,
        gold = data.money,
        earned = data.goldEarned,
        exchanged = data.goldExchanged,
        run = onchain and tonumber(onchain.remote.saveRunId) or nil,
        arrows = data.arrowCount,
        bombs = data.bombCount,
        keys = data.keys,
        outfit = data.outfit,
        items = { left = data.item.left, right = data.item.right, altL = data.item.altL, altR = data.item.altR },
        story = story,
        skills = skills,
        bag = data.bag,
        chests = setToList(data.chests),
        defeated = setToList(data.defeated),
        checkpoints = setToList(data.checkpoints),
        breakables = setToList(data.breakables),
        day = data.day,
        clock = math.floor(data.clock * 1000 + 0.5) / 1000,
        t = os.time(),
    }
end

function saveState:encode(snapshot)
    return json.encode(snapshot)
end

-- text -> table, or nil and why
function saveState:decode(text)
    if type(text) ~= "string" or text == "" then return nil, "empty save" end
    local save, err = json.decode(text)
    if type(save) ~= "table" then return nil, err or "not a save" end
    return save
end

local function knownMap(name)
    return type(name) == "string" and name:match("^[%w_]+$") and name ~= "menu"
        and love.filesystem.getInfo("maps/" .. name .. ".lua") ~= nil
end

-- Turns a decoded save into game data (replacing `data`). Returns the map and
-- position to load, or nil and why the save can't be used.
function saveState:apply(save)
    if type(save) ~= "table" then return nil, "not a save" end
    if tonumber(save.v) ~= self.VERSION then return nil, "this save is from another version of the game" end
    if not knownMap(save.map) then return nil, "this save points to an unknown place" end

    createNewSave()
    data.maxHealth = int(save.maxHp, 1, 20, 4)
    local hp = tonumber(save.hp) or data.maxHealth
    player.health = math.max(0.5, math.min(data.maxHealth, math.floor(hp * 2 + 0.5) / 2))
    data.money = int(save.gold, 0, 999999, 0)
    data.goldEarned = int(save.earned, 0, 999999, 0)
    data.goldExchanged = int(save.exchanged, 0, 999999, 0)
    data.arrowCount = int(save.arrows, 0, data.maxArrowCount, data.arrowCount)
    data.bombCount = int(save.bombs, 0, data.maxBombCount, data.bombCount)
    data.keys = int(save.keys, 0, 99, 0)
    data.outfit = int(save.outfit, 1, 9, 1)
    data.day = int(save.day, 1, 99999, 1)
    local clock = tonumber(save.clock)
    data.clock = (clock and clock == clock) and math.max(0, math.min(0.999, clock)) or 0.12

    local story = type(save.story) == "table" and save.story or {}
    for key, kind in pairs(STORY) do
        if kind == "bool" then
            data.story[key] = story[key] == true
        elseif kind == "day" then
            data.story[key] = int(story[key], 0, 99999, 0)
        else
            data.story[key] = int(story[key], 0, 99, 0)
        end
    end
    local skills = type(save.skills) == "table" and save.skills or {}
    for key in pairs(SKILLS) do data.skills[key] = skills[key] == true end
    if data.story.rickDefeated then data.story.manaUnlocked = true end

    local items = type(save.items) == "table" and save.items or {}
    for _, slot in ipairs({ "left", "right", "altL", "altR" }) do
        local item = items[slot]
        if ITEMS[item] and (item ~= "staff" or data.skills.laserStaff) then
            data.item[slot] = item
        end
    end

    local bag = type(save.bag) == "table" and save.bag or {}
    for id in pairs(mobLoot.ITEMS) do
        local n = int(bag[id], 0, 9999, 0)
        if n > 0 then data.bag[id] = n end
    end

    data.chests = listToSet(save.chests)
    data.defeated = listToSet(save.defeated)
    data.checkpoints = listToSet(save.checkpoints)
    data.breakables = listToSet(save.breakables)
    if type(save.cp) == "string" and #save.cp <= 80 then data.lastCheckpoint = save.cp end

    local x, y = tonumber(save.x), tonumber(save.y)
    if x and y and (x < 0 or y < 0 or x > 20000 or y > 20000) then x, y = nil, nil end
    data.map = save.map
    return save.map, x, y
end

-- ------------------------------------------------------------------ this device

function saveState:writeLocal(text)
    local ok = pcall(love.filesystem.write, self.FILE, text)
    return ok
end

-- the save on this device as a table, or nil
function saveState:readLocal()
    if not love.filesystem.getInfo(self.FILE) then return nil end
    local ok, text = pcall(love.filesystem.read, self.FILE)
    if not ok then return nil end
    return (self:decode(text))
end

function saveState:deleteLocal()
    if love.filesystem.getInfo(self.FILE) then love.filesystem.remove(self.FILE) end
end

-- ------------------------------------------------------------------ saving

-- Saves the game where the player stands: always on this device, and on-chain
-- when a wallet is connected. onChainDone(ok) is called after the chain answers.
function saveState:saveNow(onChainDone)
    local text = self:encode(self:snapshot(loadedMap, player:getX(), player:getY()))
    self:writeLocal(text)

    if onchain:canSave() then
        showToast("Saving on-chain: confirm in your wallet", 3)
        self.chainSaving = true
        onchain:start("save", { data = text }, function(remote, ok)
            self.chainSaving = false
            if ok then
                showToast("Journey saved on-chain!", 3)
            else
                showToast("Saved on this device only. " .. (remote.error or ""), 4)
            end
            if onChainDone then onChainDone(ok) end
        end)
        return "chain"
    end

    if onchain:available() and onchain.remote.saves == "1" then
        showToast("Saved on this device. Connect a wallet (Menu) to save on-chain.", 4)
    else
        showToast("Game saved", 2)
    end
    return "local"
end
