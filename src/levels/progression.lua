-- Levels. The hero earns experience (XP) by defeating monsters and finishing
-- quests (src/levels/quests.lua); each level brings a point to spend in the
-- Adventure Book (src/ui/book.lua) on one of four attributes:
--   Vitality   +1 heart            (up to 3 points)
--   Strength   +15% sword damage   (up to 5)
--   Spirit     +10 mana            (up to 5)
--   Endurance  +12 stamina         (up to 5)
-- The level comes from data.xp, and the points left are the levels earned less
-- the points spent (data.stats), so the two can never disagree.

progression = {}

progression.STATS = {
    { id = "vitality", name = "Vitality", max = 3, about = "+1 heart a point", icon = "heart" },
    { id = "strength", name = "Strength", max = 5, about = "+15% sword damage a point", icon = "sword" },
    { id = "spirit", name = "Spirit", max = 5, about = "+10 mana a point", icon = "drop" },
    { id = "endurance", name = "Endurance", max = 5, about = "+12 stamina a point", icon = "gem" },
}

local SWORD_POWER = 1.2 -- the hero's cut before any Strength (src/player.lua)
local STAMINA = 100
-- what a monster is worth: by its type (slimes by their form: blue, yellow, red)
local KILL_XP = { bat = 4, eye = 6, skeleton = 8, slime = { 3, 5, 7 } }

-- XP from one level to the next
function progression.toNext(level)
    return 25 + 15 * (level - 1)
end

-- the level, the XP into it, and the XP it takes to the next
function progression:level()
    local xp = data.xp or 0
    local level = 1
    while xp >= self.toNext(level) do
        xp = xp - self.toNext(level)
        level = level + 1
    end
    return level, xp, self.toNext(level)
end

function progression:stat(id)
    return (data.stats and data.stats[id]) or 0
end

function progression:spent()
    local n = 0
    for _, s in ipairs(self.STATS) do n = n + self:stat(s.id) end
    return n
end

-- points earned and not yet spent
function progression:points()
    return math.max(0, self:level() - 1 - self:spent())
end

-- XP earned (shown over (x, y) when given); a new level heals the hero and says so
function progression:gain(amount, x, y)
    if not amount or amount <= 0 then return end
    local before = self:level()
    data.xp = (data.xp or 0) + amount
    if x and y then floatTexts:spawn(x, y - 12, "+" .. amount .. " XP", { 0.8, 0.66, 1 }, { life = 0.9 }) end
    local after = self:level()
    if after > before then self:leveledUp(after) end
end

function progression:leveledUp(level)
    player.health = data.maxHealth
    staff.mana = staff:maxMana()
    floatTexts:spawn(player:getX(), player:getY() - 22, "LEVEL UP!", { 1, 0.86, 0.4 }, { big = true, life = 1.4 })
    dj.play("sounds/items/manaFull.wav", "static", "effect", 0.8, 1.25)
    if data.story.bookGiven then
        showToast("Level " .. level .. "!  A point to spend in your Adventure Book (B)", 4)
    else
        showToast("Level " .. level .. "!  Spend its point in an Adventure Book, from the Adventurers' Guild", 4)
    end
end

-- a monster defeated for good (src/enemies/enemy.lua)
function progression:killed(enemy)
    local xp = KILL_XP[enemy.type]
    if type(xp) == "table" then xp = xp[enemy.form or 1] or xp[1] end
    if not xp then return end
    local x, y
    if enemy.physics then x, y = enemy.physics:getPosition() end
    self:gain(xp, x, y)
end

function progression:canSpend(id)
    for _, s in ipairs(self.STATS) do
        if s.id == id then return self:points() > 0 and self:stat(id) < s.max end
    end
    return false
end

-- a point on an attribute (from the book)
function progression:spend(id)
    if not self:canSpend(id) then return false end
    data.stats[id] = self:stat(id) + 1
    if id == "vitality" then
        data.maxHealth = data.maxHealth + 1
        player.health = math.min(data.maxHealth, player.health + 1)
    end
    self:apply()
    return true
end

-- the attributes at work on the hero (mana: staff:maxMana adds manaBonus)
function progression:apply()
    player.swordPower = SWORD_POWER * (1 + 0.15 * self:stat("strength"))
    player.staminaMax = STAMINA + 12 * self:stat("endurance")
    player.stamina = math.min(player.stamina or player.staminaMax, player.staminaMax)
end

function progression:manaBonus()
    return 10 * self:stat("spirit")
end
