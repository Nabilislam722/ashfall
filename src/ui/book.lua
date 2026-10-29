-- The Adventure Book (B; J opens it at the journal): the hero's book, from the
-- Adventure Book pack in sprites/ui/book. It opens, turns its pages between
-- four bookmarks, and closes again; while it's open the world waits.
--
--   Profile    the hero's level, experience and numbers; points to spend on
--              Vitality, Strength, Spirit and Endurance (src/levels/progression.lua)
--   Journal    the quests (src/levels/quests.lua): the story, side quests and
--              bounties; who asked, where, the steps so far, the reward; Track
--              one to have its next step as the Goal under the HUD
--   World Map  the island with every place found and the roads between them
--              (src/levels/places.lua); a place's page links to its roads and
--              its quests, and a quest's place links back here
--   Inventory  supplies, monster loot for the guild, arms and skills
--
-- Keys: left/right (A/D, Tab) turn the page, up/down (W/S) choose, Enter or
-- Space acts (spend a point, track a quest), 1-4 jump to a bookmark, B or Esc
-- closes. The mouse works on everything.

book = { active = false, state = nil, tab = 1, statSel = 1 }

local FRAME = 272                         -- one frame of the book's sheets
local OPEN_FRAMES, OPEN_TIME = 12, 0.03   -- the cover opening (seconds a frame)
local TURN_FRAMES, TURN_TIME = 15, 0.026  -- a page turned to another bookmark
local RISE_TIME = 0.24                    -- the closed book rising into view
local SINK_TIME = 0.18                    -- ...and sinking away when it closes
local CLOSE_TIME = 0.022                  -- the cover shutting (seconds a frame)
-- the riffle once the cover's open: pages flipping past, fast, then slowing to
-- land on the page asked for (seconds each page takes)
local RIFFLE = { 0.15, 0.1, 0.075, 0.075, 0.1, 0.17 }
local FADE_IN = 0.2                       -- the page's writing coming up
local DIM = 0.6                           -- the world behind, darkened
-- the open book in its frame: the pages, and room to write on each
local L = { x = 28, y = 94, w = 99, h = 148 }
local R = { x = 147, y = 94, w = 96, h = 148 }
local BOOK = { x = 13, y = 84, w = 246, h = 183 } -- (the whole open book)

-- the bookmarks: the colour's row in bookmarks.png, the title ribbon's row in
-- titles.png, and the heading's word there
local TABS = {
    { id = "profile", name = "Profile", mark = 0, ribbon = 0, word = { 5, 416, 48, 8 } },
    { id = "journal", name = "Journal", mark = 56, ribbon = 2, word = { 5, 448, 49, 8 } },
    { id = "map", name = "World Map", mark = 20, ribbon = 1, word = { 129, 416, 60, 8 } },
    { id = "bag", name = "Inventory", mark = 168, ribbon = 6, word = { 94, 432, 64, 8 } },
}

-- pieces of elements.png
local EL = {
    frame = { 9, 346, 46, 44 }, badge = { 334, 449, 13, 14 },
    pipEmpty = { 15, 470, 4, 9 }, pipOrange = { 15, 489, 4, 10 }, pipBlue = { 15, 502, 4, 10 },
    rowTan = { 412, 100, 82, 11 }, rowTeal = { 100, 114, 86, 12 }, bullet = { 404, 104, 4, 5 },
    button = { 302, 109, 40, 12 }, plus = { 381, 430, 5, 6 }, check = { 317, 520, 9, 10 },
    heart = { 404, 570, 9, 9 }, drop = { 405, 597, 7, 11 }, coin = { 320, 483, 10, 10 }, gem = { 355, 482, 9, 11 },
    arrowR = { 351, 558, 7, 12 },
}
-- pieces of places.png: the island, each place's medallion and its marker on
-- the island (plain, and lit up)
local ISLAND = { 248, 0, 103, 102 }
local MEDALLION = { fortress = { 3, 1, 45, 45 }, cave = { 51, 1, 45, 45 }, cabin = { 99, 1, 45, 45 },
    lake = { 147, 1, 45, 45 }, ruins = { 195, 1, 45, 45 } }
local MARKER = {
    fortress = { { 353, 11, 21, 20 }, { 385, 11, 21, 20 } }, cave = { { 481, 11, 11, 10 }, { 497, 11, 11, 10 } },
    ruins = { { 365, 45, 23, 14 }, { 413, 45, 23, 14 } }, cabin = { { 357, 68, 21, 13 }, { 389, 68, 21, 13 } },
    lake = { { 429, 78, 18, 17 }, { 461, 78, 18, 17 } },
}

local INK = { 0.27, 0.18, 0.13 }
local FADED = { 0.52, 0.41, 0.31 }
local RED = { 0.64, 0.2, 0.13 }
local LINK = { 0.16, 0.3, 0.62 }
local WHITE = { 1, 0.97, 0.9 }
local GREEN = { 0.2, 0.45, 0.2 }

local ITEM_NAMES = { sword = "Sword", bow = "Bow", boomerang = "Boomerang", bomb = "Bombs", grapple = "Grapple",
    fire = "Flame", staff = "Storm Staff" }

----------------------------------------------------------------------- drawing

local bs, ox, oy = 1, 0, 0 -- the book's scale and where its frame's corner is on the screen
local alpha = 1            -- the writing on the page (fading in)
local F = nil              -- the book's fonts, for this scale
local fontScale = nil
local quads = {}

local function fonts()
    if fontScale == bs then return end
    fontScale = bs
    local vt = "fonts/vt323/VT323-Regular.ttf"
    F = {
        title = love.graphics.newFont(vt, math.floor(11 * bs + 0.5)),
        body = love.graphics.newFont(vt, math.floor(8.5 * bs + 0.5)),
        small = love.graphics.newFont(vt, math.floor(7 * bs + 0.5)),
        badge = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", math.floor(5 * bs + 0.5)),
        hint = love.graphics.newFont(vt, math.floor(5.5 * scale + 0.5)),
    }
end

local function quad(image, r)
    local key = r[1] .. "," .. r[2] .. "," .. r[3] .. "," .. r[4]
    quads[image] = quads[image] or {}
    if not quads[image][key] then
        quads[image][key] = love.graphics.newQuad(r[1], r[2], r[3], r[4], image:getDimensions())
    end
    return quads[image][key]
end

local function color(c, a)
    love.graphics.setColor(c[1], c[2], c[3], (a or 1) * alpha)
end

-- a piece of a sheet (r: its rectangle; nil for the whole image) at (x, y) on the book
local function piece(image, r, x, y, s, a, rot)
    love.graphics.setColor(1, 1, 1, (a or 1) * alpha)
    s = (s or 1) * bs
    if r then
        love.graphics.draw(image, quad(image, r), ox + x * bs, oy + y * bs, rot or 0, s, s)
    else
        love.graphics.draw(image, ox + x * bs, oy + y * bs, rot or 0, s, s)
    end
end

local function el(name, x, y, s, a)
    piece(sprites.book.elements, EL[name], x, y, s, a)
end

-- an icon centred on (x, y): an element, or the game's own sword
local function icon(name, x, y, a)
    if name == "sword" then
        local sword = sprites.items.sword
        love.graphics.setColor(1, 1, 1, (a or 1) * alpha)
        love.graphics.draw(sword, ox + x * bs, oy + y * bs, -math.pi / 4, bs * 0.8, bs * 0.8, sword:getWidth() / 2, sword:getHeight() / 2)
    elseif EL[name] then
        local r = EL[name]
        el(name, x - r[3] / 2, y - r[4] / 2, 1, a)
    end
end

local function write(text, x, y, font, c, w, align, a)
    love.graphics.setFont(font)
    color(c, a)
    if w then
        love.graphics.printf(text, ox + x * bs, oy + y * bs, w * bs, align or "left")
    else
        love.graphics.print(text, ox + x * bs, oy + y * bs)
    end
end

-- how tall text is, wrapped to w (book pixels)
local function height(text, font, w)
    local _, lines = font:getWrap(text, w * bs)
    return #lines * font:getHeight() / bs
end

local function lineH(font) return font:getHeight() / bs end

-- 0 -> 1 as t goes from a to b, and a tween that overshoots a little and settles
local function span(t, a, b) return math.max(0, math.min(1, (t - a) / (b - a))) end
local function easeOutBack(t)
    t = math.max(0, math.min(1, t))
    return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
end

-- the mouse, in book pixels
local function mouse()
    local mx, my = love.mouse.getPosition()
    return (mx - ox) / bs, (my - oy) / bs
end

local function inside(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

-- something to click this frame; true while the mouse is over it
function book:hit(x, y, w, h, fn)
    table.insert(self.hits, { x = x, y = y, w = w, h = h, fn = fn })
    local mx, my = mouse()
    return inside(mx, my, x, y, w, h)
end

-- a row of pips: `n` of them, `filled` (0..1) lit
local function pips(x, y, n, filled, lit)
    local on = math.floor(n * math.max(0, math.min(1, filled)) + 0.0001)
    for i = 1, n do
        el(i <= on and (lit or "pipOrange") or "pipEmpty", x + (i - 1) * 5, y + (i <= on and 0 or 0.5))
    end
end

-- who a quest is from, in a frame (their face, or the place's medallion)
local function portrait(q, x, y)
    el("frame", x, y)
    local cx, cy = x + 23, y + 22
    if q.look then
        local image, face = npcs:face(q.look)
        if image then
            local _, _, w, h = face:getViewport()
            piece(image, { face:getViewport() }, cx - w * 0.85, cy - h * 0.85, 1.7)
            return
        end
    elseif q.portrait == "rick" or q.portrait == "demonLord" then
        local image = q.portrait == "rick" and sprites.enemies.rickPortrait or sprites.enemies.demonLordPortrait
        local s = 30 / image:getHeight()
        piece(image, nil, cx - image:getWidth() * s / 2, cy - image:getHeight() * s / 2, s)
        return
    end
    local p = places:get(q.place)
    if p then piece(sprites.book.places, MEDALLION[p.art], cx - 15.75, cy - 15.75, 0.7) end
end

----------------------------------------------------------------------- the pages

local function rankTitle()
    local s = data.story
    if s.gulaFrozen then return "Bane of Gula" end
    if data.defeated.demonLord then return "Breaker of the Demon General" end
    if s.rickDefeated then return "Defender of Willowbrook" end
    return "A wanderer"
end

function book:drawProfile()
    -- the hero
    el("frame", L.x, L.y)
    piece(sprites.npc.hero, nil, L.x + 23 - 9.5 * 1.5, L.y + 22 - 10.5 * 1.5, 1.5)
    write("Hero", L.x + 50, L.y, F.title, INK)
    write(rankTitle(), L.x + 50, L.y + 11, F.small, FADED, 50)
    local level, into, need = progression:level()
    el("badge", L.x + 50, L.y + 28)
    write(tostring(level), L.x + 50, L.y + 28 + (14 - lineH(F.badge)) / 2, F.badge, WHITE, 13, "center")
    write("Level " .. level, L.x + 66, L.y + 28, F.body, INK)

    local y = L.y + 49
    write("Experience", L.x, y, F.small, FADED)
    write(into .. " / " .. need .. " XP", L.x, y, F.small, FADED, L.w, "right")
    pips(L.x, y + 9, 20, into / need)

    local power = player.swordPower or 1.2
    local rows = {
        { "heart", "Hearts", data.maxHealth },
        { "drop", "Mana", staff:maxMana() },
        { "gem", "Stamina", player.staminaMax },
        { "sword", "Sword", string.format("%.1f", power) },
        { "coin", "Gold", data.money },
        { nil, "Day", data.day },
    }
    y = L.y + 68
    for _, row in ipairs(rows) do
        el("rowTan", L.x + 14, y)
        if row[1] then icon(row[1], L.x + 6, y + 5.5) end
        write(row[2], L.x + 17, y + 0.5, F.small, INK)
        write(tostring(row[3]), L.x + 14, y + 0.5, F.small, INK, 79, "right")
        y = y + 13
    end

    -- the attributes
    write("Attributes", R.x, R.y, F.title, INK)
    local points = progression:points()
    write(points > 0 and ("Points to spend: " .. points) or "No points to spend", R.x, R.y + 11, F.small,
        points > 0 and RED or FADED)
    for i, s in ipairs(progression.STATS) do
        local y = R.y + 25 + (i - 1) * 27
        local over = self:hit(R.x, y - 1, R.w, 22, function() self.statSel = i end)
        if over then self.statSel = i end
        local chosen = self.statSel == i
        if chosen then el("rowTeal", R.x + 11, y - 1) end
        icon(s.icon, R.x + 5, y + 5)
        write(s.name, R.x + 14, y - 0.5, F.body, chosen and WHITE or INK)
        local have = progression:stat(s.id)
        for k = 1, s.max do el(k <= have and "pipOrange" or "pipEmpty", R.x + 58 + (k - 1) * 5, y + 1) end
        local can = progression:canSpend(s.id)
        el("plus", R.x + 89, y + 1, 1.6, can and 1 or 0.3)
        self:hit(R.x + 87, y - 1, 12, 12, function() self:spend(i) end)
        write(s.about, R.x + 14, y + 11, F.small, FADED)
    end
    write("A point for every level. Monsters and quests bring XP.", R.x, R.y + 134, F.small, FADED, R.w)
end

-- the quests in the order the journal lists them
function book:questOrder()
    local list = {}
    for _, kind in ipairs(quests.KINDS) do
        for _, q in ipairs(quests:list(kind.id)) do table.insert(list, q) end
    end
    return list
end

function book:drawJournal()
    local tracked = quests:tracked()
    local y = L.y
    local any = false
    for _, kind in ipairs(quests.KINDS) do
        local list = quests:list(kind.id)
        if #list > 0 and y < L.y + L.h - 12 then
            any = true
            write(kind.name, L.x, y, F.small, RED)
            y = y + 9
            for _, q in ipairs(list) do
                if y > L.y + L.h - 11 then break end
                local done = quests:state(q) == "done"
                self:hit(L.x, y, L.w, 11, function() self.questSel = q.id end)
                local chosen = self.questSel == q.id
                el(chosen and "rowTeal" or "rowTan", L.x + 11, y - (chosen and 0.5 or 0))
                if done then
                    el("check", L.x + 1, y + 0.5, 0.9)
                elseif tracked == q then
                    el("arrowR", L.x + 2, y - 0.5, 0.95)
                else
                    el("bullet", L.x + 3, y + 3)
                end
                local title = q.title
                while F.small:getWidth(title) > 78 * bs and #title > 4 do title = title:sub(1, -5) .. "..." end
                write(title, L.x + 14, y, F.small, chosen and WHITE or (done and FADED or INK))
                y = y + 13
            end
            y = y + 2
        end
    end
    if not any then write("No quests yet.", L.x, L.y, F.body, FADED) end

    -- the quest chosen
    local q = self.questSel and quests:get(self.questSel)
    if not q or quests:state(q) == "hidden" then
        write("Choose a quest on the left.", R.x, R.y, F.body, FADED, R.w)
        return
    end
    local done = quests:state(q) == "done"
    write(q.title, R.x, R.y, F.title, INK, R.w)
    y = R.y + height(q.title, F.title, R.w)
    local kindName = ""
    for _, k in ipairs(quests.KINDS) do if k.id == q.kind then kindName = k.name end end
    write(kindName .. (done and "  -  complete" or (tracked == q and "  -  tracked" or "")), R.x, y, F.small, done and GREEN or RED)
    y = y + 10

    portrait(q, R.x, y)
    write("From", R.x + 50, y + 2, F.small, FADED)
    write(q.giver or "-", R.x + 50, y + 9, F.body, INK, 50)
    write("Where", R.x + 50, y + 22, F.small, FADED)
    local place = places:get(q.place)
    local over = self:hit(R.x + 50, y + 29, 50, 9, function() self:showPlace(q.place) end)
    write(place and place.name or "?", R.x + 50, y + 29, F.body, over and RED or LINK, 50)
    y = y + 47

    write(q.about, R.x, y, F.small, FADED, R.w)
    y = y + height(q.about, F.small, R.w) + 3

    local current = quests:current(q) or #q.steps
    for i = 1, current do
        local step = q.steps[i]
        local stepDone, n, total = quests:step(step)
        if stepDone then el("check", R.x, y + 0.5, 0.75) else el("bullet", R.x + 2, y + 3) end
        local text = quests:stepText(step)
        write(text, R.x + 9, y, F.small, stepDone and FADED or INK, R.w - 9)
        y = y + height(text, F.small, R.w - 9)
        if total and not stepDone then
            pips(R.x + 9, y + 1, math.min(17, total), n / total, "pipBlue")
            y = y + 12
        end
        y = y + 1
    end

    local reward = "Reward: +" .. (q.xp or 0) .. " XP" .. (q.reward and ("  -  " .. q.reward) or "")
    local footY = done and (R.y + R.h) or (R.y + 136)
    write(reward, R.x, math.max(y + 1, footY - height(reward, F.small, R.w)), F.small, GREEN, R.w)
    if not done then
        local isTracked = tracked == q
        local bx, by = R.x + R.w - 40, R.y + 138
        local press = self:hit(bx, by, 40, 12, function() self:track(q) end)
        el("button", bx, by, 1, (isTracked and 0.75 or 1))
        write(isTracked and "Tracked" or "Track", bx, by + 1, F.small, press and { 1, 0.85, 0.4 } or WHITE, 40, "center")
    end
end

function book:drawMap()
    local ix, iy = L.x - 2, L.y + 2
    piece(sprites.book.places, ISLAND, ix, iy)
    -- the roads between the places found
    for i, p in ipairs(places.LIST) do
        for _, linkId in ipairs(p.links) do
            local other = places:get(linkId)
            if other and linkId > p.id and places:known(p.id) and places:known(linkId)
                and (places:visited(p.id) or places:visited(linkId)) then
                local x1, y1, x2, y2 = ix + p.x, iy + p.y, ix + other.x, iy + other.y
                local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
                for k = 4, d - 4, 4 do
                    local t = k / d
                    local dx, dy = ox + (x1 + (x2 - x1) * t) * bs, oy + (y1 + (y2 - y1) * t) * bs
                    color(INK, 0.55)
                    love.graphics.rectangle("fill", dx - bs * 0.5, dy - bs * 0.5, bs * 2.5, bs * 2.5)
                    color({ 1, 0.93, 0.68 })
                    love.graphics.rectangle("fill", dx, dy, bs * 1.5, bs * 1.5)
                end
            end
        end
    end
    -- the places: lit when chosen; a place heard of but not been to is faint
    local now = love.timer.getTime()
    for _, p in ipairs(places.LIST) do
        if places:known(p.id) then
            local m = MARKER[p.art]
            local chosen = self.placeSel == p.id
            local w, h = m[1][3], m[1][4]
            local over = self:hit(ix + p.x - w / 2 - 2, iy + p.y - h / 2 - 2, w + 4, h + 4, function() self.placeSel = p.id end)
            piece(sprites.book.places, (chosen or over) and m[2] or m[1], ix + p.x - w / 2, iy + p.y - h / 2, 1,
                places:visited(p.id) and 1 or 0.45)
            if loadedMap == p.id then
                local bob = math.sin(now * 4) * 1.2
                piece(sprites.npc.hero, { 0, 0, 16, 18 }, ix + p.x - 4, iy + p.y - h / 2 - 10 + bob, 0.5)
            end
        end
    end
    local found, total = places:countVisited()
    write("Places found: " .. found .. " / " .. total, L.x, iy + 106, F.small, FADED)
    write("Choose a place to read about it, and the roads and quests there.", L.x, iy + 115, F.small, FADED, L.w)

    -- the place chosen
    local p = self.placeSel and places:get(self.placeSel)
    if not p or not places:known(p.id) then return end
    local visited = places:visited(p.id)
    piece(sprites.book.places, MEDALLION[p.art], R.x, R.y, 1, visited and 1 or 0.5)
    write(p.name, R.x + 49, R.y + 2, F.title, INK, 50)
    local status = loadedMap == p.id and "You are here" or (visited and "Visited" or "Not yet visited")
    write(status, R.x + 49, R.y + 2 + height(p.name, F.title, 50), F.small, loadedMap == p.id and RED or FADED, 50)
    local y = R.y + 49
    if visited then
        write(p.about, R.x, y, F.small, FADED, R.w)
        y = y + height(p.about, F.small, R.w) + 3
    else
        write("Nobody you know has been there yet.", R.x, y, F.small, FADED, R.w)
        y = y + 12
    end

    write("Roads lead to", R.x, y, F.small, RED)
    y = y + 8
    for _, linkId in ipairs(p.links) do
        local known = places:known(linkId)
        if known then
            local over = self:hit(R.x + 6, y, R.w - 6, 8, function() self.placeSel = linkId end)
            write(places:name(linkId), R.x + 6, y, F.small, over and RED or LINK)
        else
            write("???", R.x + 6, y, F.small, FADED)
        end
        y = y + 8
    end

    local list = quests:at(p.id)
    if #list > 0 then
        y = y + 2
        write("Quests here", R.x, y, F.small, RED)
        y = y + 8
        for _, q in ipairs(list) do
            local done = quests:state(q) == "done"
            if done then el("check", R.x, y + 0.5, 0.7) end
            local over = self:hit(R.x + 6, y, R.w - 6, 8, function() self:showQuest(q.id) end)
            write(q.title, R.x + 8, y, F.small, over and RED or (done and FADED or LINK))
            y = y + 8
        end
    end

    if visited then
        y = y + 2
        local n, total = places:defeated(p.id)
        if total > 0 then
            write("Monsters defeated: " .. n .. " / " .. total, R.x, y, F.small, FADED)
            y = y + 8
        end
        local shrines = places:shrines(p.id)
        if #shrines > 0 then
            local rested = 0
            for _, s in ipairs(shrines) do if s.touched then rested = rested + 1 end end
            write(rested == #shrines and "Shrine: rested here" or "Shrine: not rested yet", R.x, y, F.small,
                rested == #shrines and GREEN or FADED)
        end
    end
end

function book:drawBag()
    write("Supplies", L.x, L.y, F.title, INK)
    local rows = {
        { sprites.hud.coin, "Gold", tostring(data.money) },
        { sprites.items.arrow, "Arrows", data.arrowCount .. " / " .. data.maxArrowCount, -math.pi / 4 },
        { sprites.items.bomb, "Bombs", data.bombCount .. " / " .. data.maxBombCount },
        { nil, "Keys", tostring(data.keys) },
    }
    local y = L.y + 13
    for _, row in ipairs(rows) do
        el("rowTan", L.x + 14, y)
        local image = row[1]
        if image then
            local s = 8 / math.max(image:getWidth(), image:getHeight())
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(image, ox + (L.x + 6) * bs, oy + (y + 5.5) * bs, row[4] or 0, s * bs, s * bs,
                image:getWidth() / 2, image:getHeight() / 2)
        end
        write(row[2], L.x + 17, y + 0.5, F.small, INK)
        write(row[3], L.x + 14, y + 0.5, F.small, INK, 79, "right")
        y = y + 13
    end

    y = y + 4
    write("Monster loot", L.x, y, F.small, RED)
    write("the guild buys it", L.x, y, F.small, FADED, L.w, "right")
    y = y + 9
    local any = false
    for _, id in ipairs(mobLoot.ORDER) do
        local n = mobLoot:count(id)
        if n > 0 then
            any = true
            local item = mobLoot.ITEMS[id]
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(sprites.items.mobLoot, mobLoot:quad(id), ox + L.x * bs, oy + y * bs, 0, bs * 0.9, bs * 0.9)
            write(item.name .. "  x" .. n, L.x + 12, y, F.small, INK)
            write(item.price * n .. "g", L.x, y, F.small, FADED, L.w, "right")
            y = y + 10
        end
    end
    if not any then
        write("Nothing yet. Monsters drop ears and gems the Adventurers' Guild pays for.", L.x, y, F.small, FADED, L.w)
    end

    write("Arms", R.x, R.y, F.title, INK)
    local arms = {
        { "Left click", data.item.left }, { "Right click", data.item.right }, { "R", data.item.altL },
        { fireballs and fireballs.KEY:upper() or "E", "fireball" },
    }
    y = R.y + 13
    for _, a in ipairs(arms) do
        write(a[1], R.x, y, F.small, FADED)
        write(a[2] == "fireball" and "Fireball" or (ITEM_NAMES[a[2]] or tostring(a[2])), R.x + 40, y, F.small, INK)
        y = y + 9
    end

    y = y + 6
    write("Skills", R.x, y, F.title, INK)
    y = y + 13
    local skills = {
        { "Shadow Step", data.skills.shadowStep, "Space: dash through danger", "Master Juan teaches it" },
        { "Storm Staff", data.skills.laserStaff, "Elder Mara's staff", "-" },
        { "Mana Well", data.story.manaUnlocked or data.story.rickDefeated, "veHEMI deepens your mana", "Opens once Willowbrook is safe" },
    }
    for _, s in ipairs(skills) do
        if s[2] or s[4] ~= "-" then
            if s[2] then el("check", R.x, y + 0.5, 0.75) else el("bullet", R.x + 2, y + 3) end
            write(s[1], R.x + 9, y, F.small, s[2] and INK or FADED)
            write(s[2] and s[3] or s[4], R.x + 9, y + 8, F.small, FADED, R.w - 9)
            y = y + 8 + height(s[2] and s[3] or s[4], F.small, R.w - 9) + 3
        end
    end
end

----------------------------------------------------------------------- the book

local function frameQuad(sheet, i)
    local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
    return quad(sheet, { c * FRAME, r * FRAME, FRAME, FRAME })
end

function book:layout()
    local w, h = love.graphics.getDimensions()
    -- the ribbon over the book, the book and the hint under it (frame y 44 to
    -- 277) fill most of the screen
    bs = math.min(w * 0.92 / 250, h * 0.94 / 233)
    ox = math.floor(w / 2 - 136 * bs + 0.5)
    oy = math.floor(h / 2 - 160.5 * bs + 0.5)
    fonts()
end

-- the Adventurers' Guild hands it out (src/levels/villageStory.lua)
function book:has()
    return data.story.bookGiven == true
end

function book:open(tabId)
    if self.active then return end
    if not self:has() then
        player:outOfAmmo("No Adventure Book yet - the Adventurers' Guild hands them out")
        return
    end
    self.active = true
    self.state, self.t, self.shown, self.since = "rising", 0, 0, 0
    self.dim = 0
    for i, t in ipairs(TABS) do
        if t.id == tabId then self.tab = i end
    end
    local tracked = quests:tracked()
    local q = self.questSel and quests:get(self.questSel)
    if not q or quests:state(q) == "hidden" then self.questSel = tracked and tracked.id or nil end
    if not self.questSel then
        local first = self:questOrder()[1]
        self.questSel = first and first.id
    end
    if places:known(loadedMap or "") then self.placeSel = loadedMap end
    if TABS[self.tab].id == "journal" then quests.unread = false end
    dj.play(sounds.ui.menuOpen, "static", "effect")
end

function book:close()
    if not self.active or self.state == "closing" or self.state == "sinking" then return end
    -- (from the cover's frame it's at, if it's still opening)
    local from = OPEN_FRAMES
    if self.state == "opening" then from = math.min(OPEN_FRAMES, 1 + math.floor(self.t / OPEN_TIME)) end
    if self.state == "rising" then from = 1 end
    self.state, self.t, self.closeFrom = "closing", 0, from
    dj.play(sounds.ui.menuClose, "static", "effect")
end

-- skip to the page (a key or a click while it's still opening)
function book:hurry()
    if self.state == "rising" or self.state == "opening" or self.state == "riffle" then
        self.state, self.t, self.shown, self.since = "open", 0, 0, 0
    end
end

-- turn to a bookmark
function book:go(i)
    if self.state ~= "open" or i == self.tab or not TABS[i] then return end
    self.state, self.t = "turning", 0
    self.turnDir = i > self.tab and "Left" or "Right" -- (forward: the right-hand page goes over)
    self.toTab = i
    if TABS[i].id == "journal" then quests.unread = false end
    dj.play(sounds.ui.click, "static", "effect", 0.8, 0.75)
end

function book:goTo(id)
    for i, t in ipairs(TABS) do
        if t.id == id then self:go(i) end
    end
end

function book:showPlace(id)
    if not places:known(id) then return end
    self.placeSel = id
    self:goTo("map")
end

function book:showQuest(id)
    self.questSel = id
    self:goTo("journal")
end

function book:spend(i)
    self.statSel = i
    local s = progression.STATS[i]
    if progression:spend(s.id) then
        dj.play("sounds/items/manaFull.wav", "static", "effect", 0.6, 1.4)
    else
        dj.play(sounds.ui.click, "static", "effect", 0.6, 0.6)
    end
end

function book:track(q)
    if quests:tracked() == q then return end
    quests:track(q.id)
    dj.play(sounds.ui.select, "static", "effect")
    showToast("Tracking: " .. q.title, 2.5)
end

function book:update(dt)
    if not self.active then return end
    self.t = (self.t or 0) + dt
    local s = self.state
    -- the world darkens as it opens, and comes back as it closes
    if s == "closing" or s == "sinking" then
        self.dim = math.max(0, self.dim - dt / (OPEN_FRAMES * CLOSE_TIME + SINK_TIME))
    else
        self.dim = math.min(1, self.dim + dt / 0.35)
    end
    if s == "rising" and self.t >= RISE_TIME then
        self.state, self.t = "opening", 0
    elseif s == "opening" and self.t >= OPEN_FRAMES * OPEN_TIME then
        self.state, self.t, self.flip = "riffle", 0, 1
        self:flipSound()
    elseif s == "riffle" and self.t >= RIFFLE[self.flip] then
        self.t = self.t - RIFFLE[self.flip]
        self.flip = self.flip + 1
        if RIFFLE[self.flip] then
            self:flipSound()
        else
            self.state, self.t, self.shown, self.since = "open", 0, 0, 0
        end
    elseif s == "turning" and self.t >= TURN_FRAMES * TURN_TIME then
        self.state, self.shown = "open", 0
        self.tab = self.toTab
    elseif s == "closing" and self.t >= self.closeFrom * CLOSE_TIME then
        self.state, self.t = "sinking", 0
    elseif s == "sinking" and self.t >= SINK_TIME then
        self.active, self.state = false, nil
    elseif s == "open" then
        self.shown = self.shown + dt
        self.since = self.since + dt
    end
end

-- a page flipping past: a papery tick, never quite the same twice
function book:flipSound()
    dj.play(sounds.ui.click, "static", "effect", 0.3, 1.5 + math.random() * 0.5)
end

-- up and down through what a page lists
function book:move(dir)
    local tab = TABS[self.tab].id
    if tab == "profile" then
        self.statSel = (self.statSel - 1 + dir) % #progression.STATS + 1
    elseif tab == "journal" then
        local list = self:questOrder()
        if #list == 0 then return end
        local at = 0
        for i, q in ipairs(list) do if q.id == self.questSel then at = i end end
        self.questSel = list[(at - 1 + dir) % #list + 1].id
    elseif tab == "map" then
        local list = {}
        for _, p in ipairs(places.LIST) do if places:known(p.id) then table.insert(list, p) end end
        if #list == 0 then return end
        local at = 0
        for i, p in ipairs(list) do if p.id == self.placeSel then at = i end end
        self.placeSel = list[(at - 1 + dir) % #list + 1].id
    else
        return
    end
    dj.play(sounds.ui.click, "static", "effect", 0.4, 1.2)
end

function book:activate()
    local tab = TABS[self.tab].id
    if tab == "profile" then
        self:spend(self.statSel)
    elseif tab == "journal" then
        local q = self.questSel and quests:get(self.questSel)
        if q and quests:state(q) == "active" then self:track(q) end
    end
end

function book:keypressed(key)
    if not self.active or self.state == "closing" or self.state == "sinking" then return end
    if key == "b" or key == "escape" then return self:close() end
    if self.state == "rising" or self.state == "opening" or self.state == "riffle" then return self:hurry() end
    if key == "j" then return self:goTo("journal") end
    local n = tonumber(key)
    if n and TABS[n] then return self:go(n) end
    if key == "right" or key == "d" or key == "tab" then return self:go(self.tab % #TABS + 1) end
    if key == "left" or key == "a" then return self:go((self.tab - 2) % #TABS + 1) end
    if self.state ~= "open" then return end
    if key == "up" or key == "w" then
        self:move(-1)
    elseif key == "down" or key == "s" then
        self:move(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        self:activate()
    end
end

function book:mousepressed(x, y, button)
    if not self.active then return end
    if self.state == "rising" or self.state == "opening" or self.state == "riffle" then return self:hurry() end
    if self.state ~= "open" then return end
    if button ~= 1 then return self:close() end
    local bx, by = (x - ox) / bs, (y - oy) / bs
    for i = #(self.hits or {}), 1, -1 do
        local h = self.hits[i]
        if inside(bx, by, h.x, h.y, h.w, h.h) then
            h.fn()
            return
        end
    end
    -- a click off the book (and its bookmarks) closes it
    if not inside(bx, by, BOOK.x, BOOK.y - 40, BOOK.w + 14, BOOK.h + 40) then self:close() end
end

function book:draw()
    if not self.active then return end
    self:layout()
    local w, h = love.graphics.getDimensions()
    local s = self.state
    local progress = self.dim or 1
    love.graphics.setColor(0, 0, 0, DIM * progress)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local isOpen = s == "open" or s == "turning"
    local since = (s == "open") and self.since or 1 -- (how long the pages have been up)
    self.hits = {}

    -- the bookmarks, sliding out from behind the cover one after another (the
    -- page's own sticks out further)
    if isOpen then
        local mx, my = mouse()
        for i, t in ipairs(TABS) do
            local out = easeOutBack(span(since, 0.05 + i * 0.05, 0.25 + i * 0.05))
            if out > 0 then
                local ty = 98 + (i - 1) * 17
                local chosen = i == (s == "turning" and self.toTab or self.tab)
                local tx = 244 + ((chosen and 16 or 12) * out)
                local over = inside(mx, my, tx, ty, 16, 14)
                piece(sprites.book.bookmarks, { over and 76 or 15, t.mark, 14, 14 }, tx, ty)
                table.insert(self.hits, { x = tx, y = ty, w = 16, h = 14, fn = function() self:go(i) end })
            end
        end
    end

    -- the book: rising closed, its cover opening, pages riffling past, a page
    -- turning to another bookmark, lying open, or shutting and sinking away
    alpha = 1
    local sheet, frame = sprites.book.open, OPEN_FRAMES
    local lift, size, fade = 0, 1, 1
    if s == "rising" then
        local p = span(self.t, 0, RISE_TIME)
        frame, lift, size, fade = 1, 30 * (1 - easeOutBack(p)), 0.9 + 0.1 * easeOutBack(p), math.min(1, p * 2)
    elseif s == "opening" then
        frame = math.min(OPEN_FRAMES, 1 + math.floor(self.t / OPEN_TIME))
    elseif s == "riffle" then
        sheet = sprites.book.turnLeft
        frame = math.min(TURN_FRAMES, 1 + math.floor(self.t / RIFFLE[self.flip] * TURN_FRAMES))
    elseif s == "turning" then
        sheet = sprites.book["turn" .. self.turnDir]
        frame = math.min(TURN_FRAMES, 1 + math.floor(self.t / TURN_TIME))
    elseif s == "closing" then
        frame = math.max(1, self.closeFrom - math.floor(self.t / CLOSE_TIME))
    elseif s == "sinking" then
        local p = span(self.t, 0, SINK_TIME)
        frame, lift, size, fade = 1, 26 * p * p, 1 - 0.08 * p, 1 - p
    end
    love.graphics.setColor(1, 1, 1, fade)
    love.graphics.draw(sheet, frameQuad(sheet, frame), ox + 136 * bs, oy + (175.5 + lift) * bs, 0, bs * size, bs * size, 136, 175.5)

    if isOpen then
        -- news on a bookmark: a point to spend, a quest come in
        for i, t in ipairs(TABS) do
            local news = (t.id == "profile" and progression:points() > 0) or (t.id == "journal" and quests.unread)
            if news and since > 0.3 + i * 0.05 then
                local chosen = i == (s == "turning" and self.toTab or self.tab)
                local tx, ty = 244 + (chosen and 16 or 12), 98 + (i - 1) * 17
                el("badge", tx + 11, ty - 3, 0.6)
                write("!", tx + 11, ty - 3, F.badge, WHITE, 13 * 0.6, "center")
            end
        end
        -- the heading's ribbon, dropping in over the top of the book
        local t = TABS[s == "turning" and (self.t > TURN_FRAMES * TURN_TIME / 2 and self.toTab or self.tab) or self.tab]
        local drop = easeOutBack(span(since, 0, 0.3))
        alpha = math.min(1, since / 0.12)
        piece(sprites.book.titles, { 5, 8 + 48 * t.ribbon, 230, 46 }, 21, 44 - 14 * (1 - drop))
        piece(sprites.book.titles, t.word, 136 - t.word[3] / 2, 75 - 14 * (1 - drop))
        alpha = 1
    end

    -- the writing on the pages
    if s == "open" then
        alpha = math.min(1, math.max(0, self.shown - 0.06) / FADE_IN)
        local id = TABS[self.tab].id
        if id == "profile" then self:drawProfile()
        elseif id == "journal" then self:drawJournal()
        elseif id == "map" then self:drawMap()
        else self:drawBag() end
        alpha = 1
    end

    -- how to work it, under the book
    love.graphics.setFont(F.hint)
    local hint = "Left / Right: turn the page     Up / Down: choose     Enter: select     B or Esc: close"
    local hy = oy + 269 * bs
    love.graphics.setColor(0, 0, 0, 0.6 * progress)
    love.graphics.printf(hint, 2, hy + 2, w, "center")
    love.graphics.setColor(0.92, 0.88, 0.8, progress)
    love.graphics.printf(hint, 0, hy, w, "center")
    setWhite()
end
