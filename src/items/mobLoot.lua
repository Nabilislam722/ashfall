-- Monster drops for the Adventurers' Guild.
--
-- Every defeated monster drops its ear (the guild's proof of a hunt; a slime,
-- having none, a blob of its gel), and 1 in
-- 100 also drops a rare treasure. Drops bounce out like coins; picking one up
-- puts it in data.bag, and the guild in Willowbrook buys them for gold.

mobLoot = {}
mobLoot.RARE_CHANCE = 0.01

mobLoot.ITEMS = {
    batEar = { name = "Bat Ear", price = 2, frame = 1,
        desc = "Thin and leathery. Proof you've hunted a bat." },
    skeletonEar = { name = "Skeleton Ear", price = 4, frame = 2,
        desc = "Somehow, skeletons have ears. The guild doesn't ask questions." },
    gazerEar = { name = "Gazer Ear", price = 5, frame = 3,
        desc = "Floating eyes have tiny ears. Who knew?" },
    slimeGel = { name = "Slime Gel", price = 3, frame = 6,
        desc = "A wobbly blob from the Whispering Woods. Slimes don't have ears." },
    goldenEar = { name = "Golden Ear", price = 60, frame = 4, rare = true,
        desc = "Rare! An ear of solid gold. Collectors pay well for these." },
    soulGem = { name = "Soul Gem", price = 120, frame = 5, rare = true,
        desc = "Rare! A gem humming with trapped mana. The guild's top prize." },
}
mobLoot.ORDER = { "batEar", "skeletonEar", "gazerEar", "slimeGel", "goldenEar", "soulGem" }
mobLoot.RARES = { "goldenEar", "soulGem" }

-- which ear each monster drops
mobLoot.EAR_FOR = { bat = "batEar", skeleton = "skeletonEar", eye = "gazerEar", slime = "slimeGel" }

local quads = {}

function mobLoot:quad(id)
    local item = self.ITEMS[id]
    if not item then return nil end
    if not quads[id] then
        local sheet = sprites.items.mobLoot
        quads[id] = love.graphics.newQuad((item.frame - 1) * 10, 0, 10, 10, sheet:getDimensions())
    end
    return quads[id]
end

function mobLoot:count(id)
    return math.max(0, math.floor(tonumber(data.bag and data.bag[id]) or 0))
end

-- ears and rare treasures carried
function mobLoot:totals()
    local ears, rares = 0, 0
    for _, id in ipairs(self.ORDER) do
        if self.ITEMS[id].rare then rares = rares + self:count(id) else ears = ears + self:count(id) end
    end
    return ears, rares
end

-- gold the guild would pay for everything carried
function mobLoot:value()
    local gold = 0
    for _, id in ipairs(self.ORDER) do gold = gold + self:count(id) * self.ITEMS[id].price end
    return gold
end

local function hop()
    local angle = math.random() * math.pi * 2
    return vector(math.cos(angle), math.sin(angle)) * (18 + math.random() * 14)
end

-- a monster died at x, y
function mobLoot:drop(enemy, x, y)
    local ear = self.EAR_FOR[enemy.type]
    if ear then spawnLoot(x, y, "bag:" .. ear, true, nil, hop()) end
    if math.random() < self.RARE_CHANCE then
        local rare = self.RARES[math.random(#self.RARES)]
        spawnLoot(x, y, "bag:" .. rare, true, nil, hop())
        particleEvent("death", x, y)
    end
end

-- the player walked over a drop
function mobLoot:pickUp(id, x, y)
    local item = self.ITEMS[id]
    data.bag[id] = self:count(id) + 1
    if item.rare then
        floatTexts:spawn(x, y - 12, "RARE! " .. item.name, {1, 0.85, 0.3}, { big = true, life = 1.8 })
        showToast("Rare find: " .. item.name .. "! The Adventurers' Guild pays " .. item.price .. " gold for it.", 4)
        dj.play(sounds.items.chest, "static", "effect", 1, 1.2)
    else
        floatTexts:spawn(x, y - 10, "+1 " .. item.name, {0.95, 0.9, 0.8}, { life = 0.9 })
    end
end

-- sells every one of `id` carried; returns how many and the gold paid
function mobLoot:sell(id)
    local n = self:count(id)
    local gold = n * self.ITEMS[id].price
    data.bag[id] = 0
    data.money = data.money + gold
    data.goldEarned = data.goldEarned + gold
    return n, gold
end
