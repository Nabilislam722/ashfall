-- The quests in the Adventure Book (src/ui/book.lua): the main story, side
-- quests and the Adventurers' Guild's bounties, each with who asked, where it
-- leads (a place from src/levels/places.lua), its steps and its reward.
--
-- A quest's progress is read from the game's own record (data.story,
-- data.skills, data.defeated, data.visited, data.checkpoints), so it's always
-- right whatever happened first. The journal itself only remembers which
-- quests have been seen, which have paid out their XP, and which one is
-- tracked (data.journal); the tracked quest's next step is the Goal under the
-- HUD (src/ui/floatText.lua).

quests = {}
quests.timer = 0
quests.unread = false -- a quest came in since the journal was last read

quests.KINDS = {
    { id = "main", name = "Main Story" },
    { id = "side", name = "Side Quests" },
    { id = "bounty", name = "Bounties" },
}

local function story() return data.story end
local function been(id) return places:visited(id) end

-- the shrines rested at, and how many there are
local function shrineCount()
    local n, total = 0, 0
    for _, p in ipairs(places.LIST) do
        for _, s in ipairs(places:shrines(p.id)) do
            total = total + 1
            if s.touched then n = n + 1 end
        end
    end
    return n, total
end

-- a quest: id, kind, title, who asked (giver; look: their villager look, or
-- portrait: "rick" / "demonLord"), its place, a line about it, when it becomes
-- known, its steps ({ text, place, done = fn } or { text, place, count = fn
-- returning n, total }), and its reward (xp, and what else, in words)
quests.LIST = {
    {
        id = "willowbrook", kind = "main", title = "Ashes over Willowbrook",
        giver = "Elder Mara", look = "citizen2", place = "village",
        about = "Smoke rises over the village south of the meadow. Something is raiding Willowbrook's winter stores.",
        known = function() return true end,
        steps = {
            { text = "Get to the village of Willowbrook, south of the meadow", place = "village",
              done = function() return been("village") or story().villageIntro end },
            { text = "Stop Rick in the plaza before he eats all the food", place = "village",
              done = function() return story().rickDefeated end },
        },
        xp = 80, reward = "The villagers trade with you, and the Mana Well opens",
    },
    {
        id = "memory", kind = "main", title = "The Thief Who Forgot",
        giver = "Rick", portrait = "rick", place = "village",
        about = "Rick has given back what's left of the food... and can't remember who he is, or why he came.",
        known = function() return story().rickDefeated end,
        steps = {
            { text = "Talk to Rick", place = "village", done = function() return story().rickTalked end },
            { text = "Rest at the Sleepy Boar Inn (east ward) or wait for morning", place = "village",
              done = function()
                  local s = story()
                  return s.guildHinted or s.guildIntro or (s.rickTalked and data.day > s.rickTalkDay)
              end },
            { text = "Ask the villagers about Rick", place = "village",
              done = function() return story().guildHinted or story().guildIntro end },
            { text = "Visit the Adventurers' Guild in the south-east", place = "village",
              done = function() return story().guildIntro end },
        },
        xp = 60, reward = "Rick remembers - and the seal below the dungeon cracks",
    },
    {
        id = "gluttony", kind = "main", title = "The Demon of Gluttony",
        giver = "Rick", portrait = "rick", place = "lair",
        about = "Deep below Willowbrook, beyond the Old Dungeon, the seal on Gula's lair has cracked.",
        known = function() return story().guildIntro end,
        steps = {
            { text = "Go down through the Old Dungeon to the cracked seal", place = "dungeon",
              done = function() return been("lair") or story().gulaFrozen end },
            { text = "Face Gula, Demon of Gluttony", place = "lair", done = function() return story().gulaFrozen end },
        },
        xp = 120, reward = "Gula sleeps in Rick's ice... for now",
    },
    {
        id = "guildBook", kind = "side", title = "An Adventurer's Book",
        giver = "Mira", look = "mira", place = "village",
        about = "Every member of the Adventurers' Guild carries an Adventure Book. The guild hall is in the south-east of Willowbrook.",
        known = function() return been("village") or story().bookGiven end,
        steps = {
            { text = "Ask Mira at the Adventurers' Guild (south-east Willowbrook) for an Adventure Book", place = "village",
              done = function() return story().bookGiven end },
        },
        xp = 20, reward = "The Adventure Book ({book})", -- ({key}: the player's key, src/ui/book.lua)
    },
    {
        id = "shadowStep", kind = "side", title = "The Shadow Step",
        giver = "Master Juan", look = "juan", place = "village",
        about = "An old swordsman by Willowbrook's south-west pond teaches a way to pass through danger unharmed.",
        known = function() return story().masterHinted or data.skills.shadowStep end,
        steps = {
            { text = "Find Master Juan by the south-west pond and learn the Shadow Step", place = "village",
              done = function() return data.skills.shadowStep end },
        },
        xp = 50, reward = "The Shadow Step ({shadowStep})",
    },
    {
        id = "general", kind = "side", title = "The Demon General",
        giver = "The Demon General", portrait = "demonLord", place = "test2",
        about = "A demon in crimson armour walks the Forest Clearing. He leaves travellers be... until they come too close.",
        known = function() return been("test2") or data.defeated.demonLord end,
        steps = {
            { text = "Defeat the Demon General in the Forest Clearing", place = "test2",
              done = function() return data.defeated.demonLord == true end },
        },
        xp = 150, reward = "+1 heart and 500 gold",
    },
    {
        id = "shrines", kind = "side", title = "Pilgrim of the Shrines", place = "test",
        about = "Old shrines stand across the land, and resting at one keeps your journey safe. Rest at every one.",
        known = function() return next(data.checkpoints) ~= nil end,
        steps = { { text = "Rest at every shrine", place = "test", count = shrineCount } },
        xp = 50,
    },
    {
        id = "slimes", kind = "bounty", title = "Slime Season",
        giver = "Mira", look = "mira", place = "woods",
        about = "From the guild's notice board: the Whispering Woods are overrun. Clear them out - and keep the gel, it sells.",
        known = function() return been("woods") end,
        steps = { { text = "Defeat the slimes of the Whispering Woods", place = "woods",
                    count = function() return places:defeated("woods") end } },
        xp = 60,
    },
    {
        id = "clearing", kind = "bounty", title = "Clear the Clearing",
        giver = "Mira", look = "mira", place = "test2",
        about = "From the guild's notice board: skeletons, gazers and slimes have made the Forest Clearing their own.",
        known = function() return been("test2") end,
        steps = { { text = "Defeat the monsters of the Forest Clearing", place = "test2",
                    count = function() return places:defeated("test2") end } },
        xp = 40,
    },
}

quests.byId = {}
for _, q in ipairs(quests.LIST) do quests.byId[q.id] = q end

function quests:get(id)
    return self.byId[id]
end

-- a step: done, and (for a counted one) how far along
function quests:step(step)
    if step.count then
        local n, total = step.count()
        return total > 0 and n >= total, n, total
    end
    return step.done() and true or false
end

-- the first step still to do (nil when the quest is done)
function quests:current(q)
    for i, step in ipairs(q.steps) do
        if not self:step(step) then return i end
    end
    return nil
end

-- "hidden", "active" or "done"
function quests:state(q)
    if not q.known() then return "hidden" end
    return self:current(q) and "active" or "done"
end

-- the known quests of a kind: those under way first, then those done
function quests:list(kind)
    local active, done = {}, {}
    for _, q in ipairs(self.LIST) do
        if q.kind == kind then
            local state = self:state(q)
            if state == "active" then table.insert(active, q) elseif state == "done" then table.insert(done, q) end
        end
    end
    for _, q in ipairs(done) do table.insert(active, q) end
    return active
end

-- the known quests at a place
function quests:at(placeId)
    local list = {}
    for _, q in ipairs(self.LIST) do
        if q.place == placeId and self:state(q) ~= "hidden" then table.insert(list, q) end
    end
    return list
end

-- a step as the journal and the HUD say it (counted steps say how far along)
function quests:stepText(step)
    if step.count then
        local n, total = step.count()
        return step.text .. " (" .. math.min(n, total) .. "/" .. total .. ")"
    end
    return step.text
end

-- the quest being followed: the one chosen in the journal while it's under
-- way, else the first under way (the story first)
function quests:tracked()
    local q = data.journal and data.journal.tracked and self:get(data.journal.tracked)
    if q and self:state(q) == "active" then return q end
    for _, kind in ipairs(self.KINDS) do
        for _, other in ipairs(self:list(kind.id)) do
            if self:state(other) == "active" then return other end
        end
    end
    return nil
end

function quests:track(id)
    data.journal.tracked = id
end

-- the Goal under the HUD: the tracked quest's next step
function quests:goal()
    if not data.journal then return nil end
    local q = self:tracked()
    if not q then return nil end
    return self:stepText(q.steps[self:current(q)])
end

-- every half second: quests that have come in, and quests finished (their XP
-- is paid once, and the journal says so)
function quests:update(dt)
    self.timer = self.timer - dt
    if self.timer > 0 or gamestate ~= 1 or not data.journal then return end
    self.timer = 0.5
    local seen, finished, xp = {}, {}, 0
    for _, q in ipairs(self.LIST) do
        local state = self:state(q)
        if state ~= "hidden" and not data.journal.seen[q.id] then
            data.journal.seen[q.id] = true
            table.insert(seen, q)
        end
        if state == "done" and not data.journal.done[q.id] then
            data.journal.done[q.id] = true
            table.insert(finished, q)
            xp = xp + (q.xp or 0)
        end
    end
    if #finished > 0 then
        local title = #finished == 1 and ("Quest complete: " .. finished[1].title) or (#finished .. " quests complete")
        showToast(title .. "   +" .. xp .. " XP", 3.5)
        dj.play(sounds.items.chest, "static", "effect", 0.7, 1.15)
        progression:gain(xp, player:getX(), player:getY() - 8)
    elseif #seen > 0 then
        local title = #seen == 1 and ("New quest: " .. seen[1].title) or (#seen .. " new quests")
        showToast(title .. (data.story.bookGiven and controls:fill("   ({book}: Adventure Book)") or ""), 3.5)
    end
    if #seen > 0 then self.unread = true end
end
