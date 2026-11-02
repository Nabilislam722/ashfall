-- The New Game intro, after the opening credits of the big open-world crime
-- games: to Lavender Dome, a slow tour of the world (each place dissolving into
-- the next, its name in the corner), the bosses caught mid-fight (the picture
-- freezes and greys, and their name slams in), a wall of character panels, and
-- at the end ASHFALL, Alpha Testing. Any key or click skips it.
--
-- intro:play(onDone)   starts it (src/ui/menu.lua, for a New Game); onDone runs
--                      once, when it's over, on black
--
-- Each map is baked once, as the intro starts, into one picture (its tiles and
-- the houses, trees and decorations src/levels/structures.lua, forestDecor.lua
-- and villageDecor.lua draw), so a shot costs one draw; the characters on top
-- are drawn from their own sheets, acting out their little scenes.

intro = { active = false }

local MUSIC = "sounds/music/Lavender_Dome.mp3"
local MUSIC_VOLUME = 0.8 -- (times the player's music volume: src/utilities/settings.lua)
local MUSIC_END = 90      -- the track runs 1:30: played through, the intro leaves it playing
                          -- on into the game, fading out to end there (skipped, it goes too)
local FADE = 1.6          -- a shot dissolving into the next
local FIRST_FADE = 2      -- the first one, out of black
local END_FADE = 1.4      -- the last fade to black
local SKIP_FADE = 0.6
local BAR = 0.085         -- the letterbox bars, top and bottom: this much of the screen each
local GREY_TIME = 0.25    -- a freeze frame drains of colour over this long
local MAPS = { "test", "village", "woods", "dungeon", "test2", "lair" }

local FONT_MINI = "fonts/kenney_fontpackage/Fonts/Kenney Mini Square.ttf"
local FONT_FUTURE = "fonts/kenney_fontpackage/Fonts/Kenney Future.ttf"
local FONT_VT = "fonts/vt323/VT323-Regular.ttf"

local function clamp01(v) return math.max(0, math.min(1, v)) end
local function musicLevel() return MUSIC_VOLUME * (settings and settings.values.music or 1) end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t) t = clamp01(t); return t * t * (3 - 2 * t) end
local function easeOut(t) t = clamp01(t); return 1 - (1 - t) * (1 - t) end
local function easeOutBack(t)
    t = clamp01(t)
    return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
end
-- 0 -> 1 as t goes from a to b
local function span(t, a, b) return clamp01((t - a) / (b - a)) end
-- the same "random" number every time for the same i and seed
local function noise(i, seed) return (math.sin(i * 12.9898 + seed * 78.233) * 43758.5453) % 1 end

----------------------------------------------------------------------- drawing helpers

local A = 1 -- how much the shot being drawn shows (it may be dissolving in or out)
local function color(r, g, b, a) love.graphics.setColor(r, g, b, (a or 1) * A) end

-- a cell of a sheet laid out in a grid, cut once
local cells = {}
local function cell(image, w, h, col, row)
    local byImage = cells[image]
    if not byImage then
        byImage = {}
        cells[image] = byImage
    end
    local key = row * 256 + col
    if not byImage[key] then
        byImage[key] = love.graphics.newQuad((col - 1) * w, (row - 1) * h, w, h, image:getDimensions())
    end
    return byImage[key]
end

-- text with a hard outline all round, as the opening credits had it
local function outlined(text, x, y, fill, edge, thick)
    color(edge[1], edge[2], edge[3], edge[4] or 1)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then love.graphics.print(text, x + dx * thick, y + dy * thick) end
        end
    end
    color(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.print(text, x, y)
end

-- a soft glow: rings fading out to `radius` (ry: squashed into an ellipse)
local function glow(x, y, radius, rgb, strength, ry)
    love.graphics.setBlendMode("add")
    for ring = 1, 6 do
        local k = ring / 6
        color(rgb[1], rgb[2], rgb[3], strength / 6)
        love.graphics.ellipse("fill", x, y, radius * k, (ry or radius) * k)
    end
    love.graphics.setBlendMode("alpha")
end

-- the hero. mode: "idle", "walk", "roll" or "strike"; dir 1 faces right, -1
-- left; up: facing away
local function hero(x, y, mode, t, dir, up)
    local sheet = sprites.playerSheet
    local row, col
    if mode == "walk" then
        row, col = up and 2 or 1, 1 + math.floor(t / 0.14) % 2
    elseif mode == "roll" then
        row, col = up and 5 or 4, math.min(3, 1 + math.floor(t / 0.11))
    elseif mode == "strike" then
        row, col = up and 2 or 1, 2
    else
        row, col = up and 9 or 8, (t % 2.6 < 0.12) and 2 or 1
    end
    local shadow = sprites.playerShadow
    color(1, 1, 1)
    love.graphics.draw(shadow, x, y + 6, 0, 1, 1, shadow:getWidth() / 2, shadow:getHeight() / 2)
    love.graphics.draw(sheet, cell(sheet, 19, 21, col, row), x, y - 2, 0, dir or 1, 1, 9.5, 10.5)
end

-- a violet afterimage of the hero (the Shadow Step)
local function ghost(x, y, alpha, dir)
    local sheet = sprites.playerSheet
    color(0.42, 0.24, 0.62, alpha)
    love.graphics.draw(sheet, cell(sheet, 19, 21, 1, 8), x, y - 2, 0, dir or 1, 1, 9.5, 10.5)
end

-- the hero's sword swing, drawn as the game draws it (src/player.lua and the
-- "slice" effect in src/effects/effect.lua): after the wind-up, the sword stands
-- a quarter turn off the cut and the slice sweeps through in two frames. t: time
-- since the swing began; flip: the other way round (every other swing does);
-- front: the parts over the hero (else the ones under them)
local SWING_WINDUP, SWING_FOLLOW, SLICE_FRAME = 0.075, 0.25, 0.06
local function swing(x, y, aim, t, flip, front)
    local ft = t - SWING_WINDUP
    if ft < 0 or ft >= SWING_FOLLOW then return end
    local reach = player.swordReach
    local side = aim + (flip and math.pi / 2 or -math.pi / 2)
    local sx, sy = math.cos(side) * 12 * reach, math.sin(side) * 12 * reach
    color(1, 1, 1)
    if not front and ft < SLICE_FRAME * 2 then
        local sheet = sprites.effects.sliceAnim
        love.graphics.draw(sheet, cell(sheet, 23, 39, ft < SLICE_FRAME and 1 or 2, 1), x + math.cos(aim) * 11, y + 2 + math.sin(aim) * 11,
            aim, reach, (flip and -1 or 1) * reach, 11.5, 19.5)
    end
    if (sy > 0) == front then
        local sword = sprites.items.sword
        love.graphics.draw(sword, x + sx, y + 1 + sy, side, 1, 1, sword:getWidth() / 2, sword:getHeight() / 2)
    end
end

-- blade on blade (or blade on boss): a burst of sparks, p from 0 to 1
local function sparks(x, y, p, seed)
    love.graphics.setBlendMode("add")
    love.graphics.setLineWidth(1)
    for i = 1, 9 do
        local a = i / 9 * math.pi * 2 + seed + noise(i, seed)
        local r0, r1 = 2 + 7 * p, 5 + 13 * p
        color(1, 0.92, 0.6, 1 - p)
        love.graphics.line(x + math.cos(a) * r0, y + math.sin(a) * r0, x + math.cos(a) * r1, y + math.sin(a) * r1)
    end
    color(1, 1, 1, 0.8 * (1 - p))
    love.graphics.circle("fill", x, y, 4 * (1 - p) + 1)
    love.graphics.setBlendMode("alpha")
end

-- a blow on its way: a star flashes on it (red: dodge it)
local function glint(x, y, p, red)
    local size = 7 * math.sin(p * math.pi)
    if red then color(1, 0.25, 0.2) else color(1, 1, 0.85) end
    love.graphics.polygon("fill", x, y - size, x + size * 0.22, y, x, y + size, x - size * 0.22, y)
    love.graphics.polygon("fill", x - size, y, x, y - size * 0.22, x + size, y, x, y + size * 0.22)
end

-- a puff of shadow smoke, p from 0 to 1
local function puff(x, y, p)
    local sheet, frames = sprites.effects.magic.smokeBurst, sprites.effects.magicQuads.smokeBurst
    color(0.55, 0.4, 0.75, 0.8 * (1 - p))
    love.graphics.draw(sheet, frames[math.min(#frames, 1 + math.floor(p * #frames))], x, y, 0, 0.5, 0.5, 36, 50)
end

-- the Demon General, his feet at (x, y); facing 1 looks right
local function general(anim, frame, x, y, facing, flash)
    local image = sprites.enemies.demonLord[anim]
    frame = math.max(1, math.min(math.floor(image:getWidth() / 216), frame))
    color(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", x, y, 14, 4)
    if flash then color(1, 0.6, 0.6) else color(1, 1, 1) end
    love.graphics.draw(image, cell(image, 216, 168, frame, 1), x, y, 0, 0.5 * facing, 0.5, 85, 168)
end

-- his hellfire rising round him, power from 0 to 1
local function hellfire(x, y, t, power)
    if power <= 0 then return end
    local sheet, frames = sprites.effects.magic.flame, sprites.effects.magicQuads.flame
    glow(x, y - 28, 30, { 1, 0.12, 0.1 }, (0.5 + 0.2 * math.sin(t * 9)) * power, 40)
    love.graphics.setBlendMode("add")
    for i = 0, 4 do
        local f = 1 + math.floor(t / 0.07 + i * 3) % #frames
        color(1, 0.5, 0.4, 0.75 * power)
        love.graphics.draw(sheet, frames[f], x - 22 + i * 11, y + 3, 0, 0.7, 0.7 * power, 36, 42)
    end
    love.graphics.setBlendMode("alpha")
end

-- Gula, its middle at (x, y): 1 mouth shut, 2 open, 3 wide
local function gula(x, y, frame)
    color(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", x, y + 38, 18, 5)
    glow(x, y, 46, { 0.75, 0.3, 1 }, 0.4)
    color(1, 1, 1)
    love.graphics.draw(sprites.enemies.gulaSheet, cell(sprites.enemies.gulaSheet, 58, 54, frame, 1), x, y, 0, 1, 1, 29, 27)
end

-- a bolt of Gula's thunder striking (x, y), p from 0 to 1 of its life
local function bolt(x, y, p, seed)
    local points = {}
    for i = 0, 8 do
        local k = i / 8
        local wobble = i == 8 and 0 or (noise(i, seed) - 0.5) * 14
        table.insert(points, x + wobble + (1 - k) * (noise(9, seed) - 0.5) * 30)
        table.insert(points, y - 150 * (1 - k))
    end
    love.graphics.setBlendMode("add")
    love.graphics.setLineWidth(3)
    color(0.75, 0.5, 1, 0.8 * (1 - p))
    love.graphics.line(points)
    love.graphics.setLineWidth(1)
    color(1, 1, 1, 1 - p)
    love.graphics.line(points)
    color(0.85, 0.65, 1, 0.7 * (1 - p))
    love.graphics.circle("fill", x, y, 4 + 10 * p)
    love.graphics.setBlendMode("alpha")
end

-- where a bolt is about to fall: a ring closing in on the ground
local function warning(x, y, p)
    love.graphics.setLineWidth(1)
    color(1, 0.3, 0.9, 0.8 * p)
    love.graphics.ellipse("line", x, y + 4, 12 * (1.6 - p * 0.6), 4 * (1.6 - p * 0.6))
end

-- Rick's head, floating z above (x, y): 1 shut, 2 chomping, 3 wide
local function rick(x, y, frame, z)
    color(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", x, y + 2, 12, 4)
    color(1, 1, 1)
    love.graphics.draw(sprites.enemies.rickSheet, sprites.enemies.rickQuads[frame], x, y + 4 - z, 0, 1, 1, 19, 53)
end

local function food(x, y, kind, rot)
    color(1, 1, 1)
    love.graphics.draw(sprites.items.food, sprites.items.foodQuads[kind], x, y, rot, 1, 1, 4, 4)
end

-- a villager from the citizens' sheets (rows: down, left, right, up)
local CITIZEN_ROW = { down = 1, left = 2, right = 3, up = 4 }
local CITIZEN_IDLE = { 12, 12, 12, 6 }
local function citizen(look, x, y, facing, walking, t)
    local art = sprites.npc[look]
    local image = walking and art.walk or art.idle
    local row = CITIZEN_ROW[facing]
    local count = walking and 6 or CITIZEN_IDLE[row]
    color(1, 1, 1)
    love.graphics.draw(image, cell(image, 32, 32, 1 + math.floor(t / 0.15) % count, row), x, y, 0, 1, 1, 16, 28)
end

-- a slime of the woods (1 blue, 2 yellow, 3 red)
local SLIME_ROW = { down = 1, up = 2, left = 3, right = 4 }
local function slime(form, x, y, facing, walking, t)
    local sheets = sprites.enemies.slimes[form]
    local image = walking and sheets.walk or sheets.idle
    local count = math.floor(image:getWidth() / 64)
    color(1, 1, 1)
    love.graphics.draw(image, cell(image, 64, 64, 1 + math.floor(t / 0.11) % count, SLIME_ROW[facing]), x, y, 0, 1, 1, 32, 37)
end

local function skeleton(x, y, t, dir)
    local image, shadow = sprites.enemies.skeletonKnife, sprites.enemies.shadowMed
    color(1, 1, 1)
    love.graphics.draw(shadow, x, y + 9, 0, 1, 1, shadow:getWidth() / 2, shadow:getHeight() / 2)
    love.graphics.draw(image, cell(image, 20, 24, 1 + math.floor(t / 0.4) % 2, 1), x, y, 0, dir, 1, 10, 12)
end

----------------------------------------------------------------------- the scenes

local function villageLife(t)
    citizen("citizen2", 472, 296, "down", false, t)
    citizen("citizen3", 600, 176, "down", false, t + 0.4)
    citizen("citizen5", 704, 140 + 20 * t, "down", true, t)
    citizen("citizen1", 650 + 22 * t, 264, "right", true, t)
    citizen("tom", 880 - 18 * t, 360, "left", true, t)
    citizen("citizen4", 1000 + 20 * t, 462, "right", true, t)
end

local function woodsLife(t)
    slime(2, 408, 328, "down", false, t)
    slime(1, 440 + 9 * t, 388, "right", true, t)
    slime(1, 728, 216, "left", false, t + 0.3)
    slime(3, 696, 488, "down", false, t + 0.6)
    slime(1, 888, 440 - 6 * t, "up", true, t)
    slime(2, 840, 552, "left", false, t + 0.2)
end

local function dungeonGuards(t)
    skeleton(430, 652, t, 1)
    skeleton(532, 662, t + 0.2, -1)
    skeleton(384, 404, t + 0.1, 1)
    skeleton(578, 414, t + 0.3, -1)
end

-- the Forest Clearing: the Demon General sizes the hero up, sweeps his blade
-- (rolled clear of), takes a cut, calls up his hellfire (the hero Shadow Steps
-- back) and thrusts: freeze
local function clearingFight(t)
    local gx, gy = 486, 256
    local anim, frame, flash = "idle", 1 + math.floor(t / 0.12) % 8, false
    if t >= 1.3 and t < 2.1 then
        anim, frame = "attack", 1 + math.floor((t - 1.3) / 0.1)
    elseif t >= 2.45 and t < 2.8 then
        anim, frame, flash = "hurt", 1 + math.floor((t - 2.45) / 0.17) % 2, t < 2.6
    elseif t >= 2.9 and t < 3.75 then
        anim, frame = "special", 1 + math.floor((t - 2.9) / 0.106)
    elseif t >= 3.8 then
        anim, frame = "attack2", 1 + math.floor((t - 3.8) / 0.1)
    end
    hellfire(gx, gy, t, span(t, 2.9, 3.2) * (1 - span(t, 3.6, 3.95)))
    general(anim, frame, gx, gy, -1, flash)
    if t >= 1.12 and t < 1.44 then glint(gx - 16, gy - 34, span(t, 1.12, 1.44), true) end

    local hy = 258
    if t < 1.2 then
        hero(lerp(392, 424, t / 1.2), hy, "walk", t, 1)
    elseif t < 1.65 then
        hero(424, hy, "idle", t, 1)
    elseif t < 1.98 then
        hero(lerp(424, 402, span(t, 1.65, 1.98)), hy, "roll", t - 1.65, 1)
    elseif t < 2.25 then
        hero(402, hy, "idle", t, 1)
    elseif t < 2.4 then
        hero(lerp(402, 446, span(t, 2.25, 2.4)), hy, "walk", t, 1)
    elseif t < 3.25 then
        swing(446, hy, 0, t - 2.4, false, false)
        hero(446, hy, t < 2.725 and "strike" or "idle", t, 1)
        swing(446, hy, 0, t - 2.4, false, true)
    else
        for i = 0, 3 do ghost(lerp(446, 414, i / 4), hy, (1 - span(t, 3.25, 3.7)) * (0.25 + i * 0.12), 1) end
        hero(414, hy, "idle", t, 1)
    end
    if t >= 2.475 and t < 2.775 then sparks(468, 244, span(t, 2.475, 2.775), 1.3) end
    if t >= 3.25 and t < 3.65 then puff(446, hy + 4, span(t, 3.25, 3.65)) end
end

-- Gula's Lair: its thunder falls where the hero stands, and keeps missing
local BOLTS = { { 1.45, 240 }, { 1.95, 268 }, { 2.95, 236 }, { 3.4, 210 } }
local function lairFight(t)
    local gy = 150 + math.sin(t * 2.2) * 3
    local frame = 1
    if (t >= 1.0 and t < 1.3) or (t >= 2.4 and t < 2.8) then
        frame = 2
    elseif t >= 1.3 then
        frame = 3
    end
    gula(240, gy, frame)

    local hy = 246
    if t < 1.2 then
        hero(240, hy, "idle", t, 1, true)
    elseif t < 1.53 then
        hero(lerp(240, 268, span(t, 1.2, 1.53)), hy, "roll", t - 1.2, 1)
    elseif t < 1.7 then
        hero(268, hy, "idle", t, -1, true)
    elseif t < 2.03 then
        hero(lerp(268, 236, span(t, 1.7, 2.03)), hy, "roll", t - 1.7, -1)
    elseif t < 2.75 then
        hero(236, hy, "idle", t, -1, true)
    elseif t < 3.15 then
        for i = 0, 3 do ghost(lerp(236, 210, i / 4), hy, (1 - span(t, 2.75, 3.15)) * (0.25 + i * 0.12), -1) end
        hero(210, hy, "idle", t, -1, true)
    elseif t < 3.48 then
        hero(lerp(210, 236, span(t, 3.15, 3.48)), hy, "roll", t - 3.15, 1)
    else
        hero(236, hy, "idle", t, 1, true)
    end
    for i, b in ipairs(BOLTS) do
        if t >= b[1] - 0.4 and t < b[1] then warning(b[2], hy, span(t, b[1] - 0.4, b[1])) end
        if t >= b[1] and t < b[1] + 0.35 then bolt(b[2], hy, span(t, b[1], b[1] + 0.35), i * 3.7) end
    end
end

-- Rick, in front of the tavern: morsels fly at the hero, who steps aside, and
-- cuts one out of the air
local THROWS = { { 0.8, 1, -24 }, { 1.4, 3, 14 }, { 2.0, 2, -6 }, { 2.6, 4, 0 }, { 3.3, 1, -10 } }
local FLIGHT = 0.62
local RICK_SWING = 2.81 -- (its slice meets the fourth morsel)
local function rickScene(t)
    local rx, ry = 1162, 322
    local z = 10 + math.sin(t * 3) * 2
    local frame = 1 + math.floor(t / 0.16) % 2
    for _, th in ipairs(THROWS) do
        if t >= th[1] - 0.12 and t < th[1] + 0.1 then frame = 3 end
    end
    if t >= 3.5 then frame = 3 end
    rick(rx, ry, frame, z)

    local hy = 328
    local hyOff = 0
    if t >= 1.1 and t < 1.9 then hyOff = -12 * smooth(span(t, 1.1, 1.35)) elseif t >= 1.9 then hyOff = -12 * (1 - smooth(span(t, 1.9, 2.15))) end
    local swingT = t - RICK_SWING
    local striking = swingT >= 0 and swingT < SWING_WINDUP + SWING_FOLLOW
    local stepping = t >= 1.1 and t < 1.35
    swing(1080, hy, -0.9, swingT, true, false)
    hero(1080, hy + hyOff, stepping and "walk" or (striking and "strike" or "idle"), t, 1, stepping or striking)
    swing(1080, hy, -0.9, swingT, true, true)

    for i, th in ipairs(THROWS) do
        local p = (t - th[1]) / FLIGHT
        local cutAt = i == 4 and 0.52 or nil -- (the fourth is cut down)
        if p >= 0 and p < 1.25 and not (cutAt and p > cutAt) then
            local x = lerp(rx - 6, 1046, p)
            local y = lerp(ry - z - 24, hy - 4 + th[3], p) - math.sin(clamp01(p) * math.pi) * 14
            food(x, y, th[2], t * 9 + i)
        end
        if cutAt and p >= cutAt and p < cutAt + 0.45 then
            sparks(lerp(rx - 6, 1046, cutAt), lerp(ry - z - 24, hy - 4, cutAt) - math.sin(cutAt * math.pi) * 14, span(p, cutAt, cutAt + 0.45), 2.1)
        end
    end
end

-- the hero comes down from the shrine, and draws
local function heroScene(t)
    if t < 2.3 then
        hero(386, lerp(250, 288, t / 2.3), "walk", t, 1)
    elseif t < 2.9 then
        hero(386, 288, "idle", t, 1)
    else
        swing(386, 288, 0, t - 2.9, false, false)
        hero(386, 288, "strike", t, 1)
        swing(386, 288, 0, t - 2.9, false, true)
    end
end

-- the dark of the dungeon and the lair: shade over everything, and their lights
local function darkness(baked, t, x0, y0, x1, y1, shade)
    color(shade[1], shade[2], shade[3], shade[4])
    love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
    for _, l in ipairs(baked.lights or {}) do
        local f = l.flicker and (0.85 + 0.15 * math.sin(t * 9 + l.seed) * math.sin(t * 5.3 + l.seed * 2)) or 1
        glow(l.x, l.y, l.radius, l.color, 0.32 * f)
    end
end

----------------------------------------------------------------------- the panels and the title

local PANELS = {
    { x = 0.07, y = 0.13, w = 0.30, h = 0.42, rot = -0.035, from = -1, at = 0.3, kind = "general",
      color = { 0.42, 0.05, 0.06 }, glow = { 1, 0.32, 0.26 }, name = "THE DEMON GENERAL" },
    { x = 0.385, y = 0.11, w = 0.235, h = 0.40, rot = 0.03, from = 1, at = 0.85, kind = "gula",
      color = { 0.3, 0.06, 0.36 }, glow = { 0.85, 0.3, 1 }, name = "GULA" },
    { x = 0.64, y = 0.15, w = 0.29, h = 0.42, rot = -0.02, from = 1, at = 1.4, kind = "rick",
      color = { 0.42, 0.12, 0.04 }, glow = { 1, 0.55, 0.2 }, name = "RICK" },
    { x = 0.22, y = 0.575, w = 0.56, h = 0.29, rot = 0.012, from = -1, at = 1.95, kind = "hero",
      color = { 0.08, 0.18, 0.36 }, glow = { 0.35, 0.75, 1 }, name = "HERO" },
}

-- what's in a panel, drawn about its middle (pw x ph)
local function panelPicture(kind, pw, ph, t)
    color(1, 1, 1)
    if kind == "general" then
        local s = ph * 0.86 / 124
        local image = sprites.enemies.demonLord.idle
        love.graphics.draw(image, cell(image, 216, 168, 1 + math.floor(t / 0.12) % 8, 1), 0, ph * 0.5, 0, s, s, 105, 168)
    elseif kind == "gula" then
        local image = sprites.enemies.gulaPortrait
        local s = ph * 0.7 / image:getHeight()
        love.graphics.draw(image, 0, -ph * 0.04 + math.sin(t * 2.2) * ph * 0.015, 0, s, s, image:getWidth() / 2, image:getHeight() / 2)
    elseif kind == "rick" then
        local image = sprites.enemies.rickPortrait
        local s = ph * 0.72 / image:getHeight()
        love.graphics.draw(image, 0, -ph * 0.03, 0, s, s, image:getWidth() / 2, image:getHeight() / 2)
    else
        local s = ph * 0.5 / 21
        local held = SWING_WINDUP + SLICE_FRAME * 2 -- (past the slice: the sword held up)
        love.graphics.push()
        love.graphics.translate(0, ph * 0.12)
        love.graphics.scale(s)
        swing(0, 0, 0, held, false, false)
        hero(0, 0, "strike", 0, 1)
        swing(0, 0, 0, held, false, true)
        love.graphics.pop()
    end
end

local function drawPanel(self, p, t, w, h)
    local arrive = easeOutBack(span(t, p.at, p.at + 0.45))
    if arrive <= 0 then return end
    local pw, ph = p.w * w, p.h * h
    local cx = (p.x + p.w / 2) * w + (1 - arrive) * w * 0.7 * p.from
    local cy = (p.y + p.h / 2) * h
    local edge = math.max(2, scale * 0.7)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(p.rot)
    color(0, 0, 0)
    love.graphics.rectangle("fill", -pw / 2 - edge * 2, -ph / 2 - edge * 2, pw + edge * 4, ph + edge * 4)
    color(p.color[1], p.color[2], p.color[3])
    love.graphics.rectangle("fill", -pw / 2, -ph / 2, pw, ph)
    -- rays of the character's colour behind them
    for i = 0, 4 do
        local x = -pw / 2 + (i + 0.2) * pw / 4.6
        color(p.glow[1], p.glow[2], p.glow[3], 0.1)
        love.graphics.polygon("fill", x, -ph / 2, x + pw * 0.09, -ph / 2, x - pw * 0.05, ph / 2, x - pw * 0.14, ph / 2)
    end
    panelPicture(p.kind, pw, ph, t)
    love.graphics.setLineWidth(edge)
    color(1, 1, 1)
    love.graphics.rectangle("line", -pw / 2, -ph / 2, pw, ph)
    -- the name, on a black slip at the foot
    local f = self.fonts.panel
    love.graphics.setFont(f)
    local tw = f:getWidth(p.name)
    local sx, sy = -pw / 2 + edge * 3, ph / 2 - f:getHeight() - edge * 4
    color(0, 0, 0, 0.85)
    love.graphics.polygon("fill", sx - edge * 2, sy, sx + tw + edge * 5, sy, sx + tw + edge * 3, sy + f:getHeight() + edge,
        sx - edge * 2, sy + f:getHeight() + edge)
    color(p.glow[1], p.glow[2], p.glow[3])
    love.graphics.print(p.name, sx, sy + edge * 0.5)
    love.graphics.pop()
end

local function collage(self, t, w, h)
    color(0.04, 0.03, 0.05)
    love.graphics.rectangle("fill", 0, 0, w, h)
    for i = 0, 7 do
        color(1, 1, 1, 0.025)
        local x = (i / 7) * w * 1.4 - w * 0.2 + t * w * 0.01
        love.graphics.polygon("fill", x, 0, x + w * 0.06, 0, x - w * 0.12, h, x - w * 0.18, h)
    end
    local zoom = 1 + 0.05 * t / 6.8
    love.graphics.push()
    love.graphics.translate(w / 2, h / 2)
    love.graphics.scale(zoom)
    love.graphics.translate(-w / 2, -h / 2)
    for _, p in ipairs(PANELS) do drawPanel(self, p, t, w, h) end
    love.graphics.pop()
end

local TITLE = "ASHFALL"
local LETTER_GAP = 0.085
local TITLE_START = 0.5
local SLAM = TITLE_START + #TITLE * LETTER_GAP + 0.08 -- the last letter lands
local GOLD, EMBER = { 1, 0.84, 0.36 }, { 0.22, 0.05, 0.02 }

local function title(self, t, w, h)
    -- embers glowing up from below
    love.graphics.setBlendMode("add")
    for i = 1, 4 do
        color(1, 0.35, 0.1, (0.05 + 0.02 * math.sin(t * 2 + i)) * span(t, 0, 1.5))
        love.graphics.ellipse("fill", w / 2, h * 1.02, w * (0.2 + i * 0.12), h * (0.12 + i * 0.07))
    end
    love.graphics.setBlendMode("alpha")

    local f = self.fonts.title
    love.graphics.setFont(f)
    local tw, th = f:getWidth(TITLE), f:getHeight()
    local x0, y0 = (w - tw) / 2, h * 0.43 - th / 2
    local jolt = (t > SLAM and t < SLAM + 0.3) and (1 - (t - SLAM) / 0.3) * scale * 1.5 or 0
    local jx, jy = (noise(math.floor(t * 60), 1) - 0.5) * jolt, (noise(math.floor(t * 60), 2) - 0.5) * jolt
    for i = 1, #TITLE do
        local ch = TITLE:sub(i, i)
        local at = TITLE_START + (i - 1) * LETTER_GAP
        local p = span(t, at, at + 0.16)
        if p > 0 then
            local s = lerp(2.4, 1, easeOut(p))
            local cw = f:getWidth(ch)
            local cx = x0 + f:getWidth(TITLE:sub(1, i - 1)) + cw / 2
            -- after the slam a shine runs along the letters
            local shine = clamp01(1 - math.abs((t - SLAM - 1.0) * 6 - (i - 1) * 0.9))
            local fill = { lerp(GOLD[1], 1, shine), lerp(GOLD[2], 1, shine), lerp(GOLD[3], 1, shine), p }
            love.graphics.push()
            love.graphics.translate(cx + jx, y0 + th / 2 + jy)
            love.graphics.scale(s)
            outlined(ch, -cw / 2, -th / 2, fill, { EMBER[1], EMBER[2], EMBER[3], p }, scale * 0.9)
            love.graphics.pop()
        end
    end
    if t > SLAM then
        color(1, 0.9, 0.7, 0.35 * (1 - span(t, SLAM, SLAM + 0.45)))
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    -- a line grows under it, and ALPHA TESTING comes up on it
    local grow = smooth(span(t, SLAM + 0.3, SLAM + 1.0))
    local ly = y0 + th + scale * 1.5
    love.graphics.setLineWidth(math.max(1, scale * 0.35))
    color(GOLD[1], GOLD[2], GOLD[3], 0.8 * grow)
    love.graphics.line(w / 2 - tw * 0.45 * grow, ly, w / 2 + tw * 0.45 * grow, ly)
    local beta = self.fonts.beta
    love.graphics.setFont(beta)
    local text = "A L P H A    T E S T I N G"
    local bw = beta:getWidth(text)
    local fade = span(t, SLAM + 0.6, SLAM + 1.3)
    outlined(text, (w - bw) / 2, ly + scale * 2.5, { 0.95, 0.93, 0.88, fade }, { 0, 0, 0, fade }, math.max(1, scale * 0.3))
end

----------------------------------------------------------------------- the running order

-- len: how long a shot runs (it dissolves into the next over its last FADE
-- seconds); cam: where the camera starts and ends, x1, y1, x2, y2; zoom: how
-- close it is, from and to (times the game's own); freeze: when the picture
-- stops for the card
local SHOTS = {
    { map = "test", len = 8.0, cam = { 300, 200, 470, 380 }, zoom = { 0.5, 0.56 }, caption = "WILLOW MEADOW" },
    { map = "village", len = 8.8, cam = { 520, 330, 1150, 420 }, zoom = { 0.46, 0.48 }, caption = "WILLOWBROOK", actors = villageLife },
    { map = "woods", len = 8.0, cam = { 300, 250, 900, 450 }, zoom = { 0.5, 0.54 }, caption = "WHISPERING WOODS", actors = woodsLife },
    { map = "dungeon", len = 7.2, cam = { 480, 620, 480, 220 }, zoom = { 0.55, 0.58 }, caption = "THE OLD DUNGEON",
      actors = dungeonGuards, dark = { 0.02, 0.02, 0.06, 0.5 } },
    { map = "test2", len = 7.8, cam = { 436, 242, 444, 246 }, zoom = { 1.08, 1.12 }, caption = "FOREST CLEARING",
      actors = clearingFight, freeze = 4.3, swings = { 2.4 }, hits = { 2.475 },
      card = { name = "THE DEMON GENERAL", title = "Roams the Forest Clearing", color = { 1, 0.3, 0.24 } } },
    { map = "lair", len = 7.4, cam = { 240, 194, 240, 190 }, zoom = { 0.95, 0.98 }, caption = "GULA'S LAIR",
      actors = lairFight, freeze = 4.0, dark = { 0.05, 0.0, 0.08, 0.42 },
      card = { name = "GULA", title = "Demon of Gluttony", color = { 0.85, 0.35, 1 } } },
    { map = "village", len = 7.0, cam = { 1112, 306, 1120, 304 }, zoom = { 1.15, 1.2 }, actors = rickScene, freeze = 3.7, swings = { RICK_SWING },
      card = { name = "RICK", title = "The Bottomless Stomach", color = { 1, 0.55, 0.2 } } },
    { map = "test", len = 7.0, cam = { 386, 276, 386, 282 }, zoom = { 1.2, 1.3 }, actors = heroScene, freeze = 3.05, swings = { 2.9 },
      card = { name = "HERO", title = "Defender of Willowbrook", color = { 0.4, 0.78, 1 } } },
    { screen = collage, len = 6.8, fadeOut = 1.2 },
    { screen = title, len = 8.4, gap = 0.4 },
}

local TOTAL = 0
do
    local at = 0
    for i, shot in ipairs(SHOTS) do
        if i > 1 then
            local prev = SHOTS[i - 1]
            at = shot.gap and (prev.at + prev.len + shot.gap) or (prev.at + prev.len - FADE)
        end
        shot.at = at
        TOTAL = math.max(TOTAL, at + shot.len)
    end
end
intro.TOTAL = TOTAL

-- the sounds that go with the pictures: { when, sound, volume }
local CUES = {}
do
    local function cue(at, sound, volume) table.insert(CUES, { at = at, sound = sound, volume = volume }) end
    for _, shot in ipairs(SHOTS) do
        if shot.freeze then
            cue(shot.at + shot.freeze, "sounds/domain/slam.wav", 0.45)
            cue(shot.at + shot.freeze + 0.12, "sounds/domain/shing.wav", 0.4)
        end
        for _, sw in ipairs(shot.swings or {}) do cue(shot.at + sw + SWING_WINDUP, "sounds/items/sword.wav", 0.5) end
        if shot.actors == lairFight then
            for _, b in ipairs(BOLTS) do cue(shot.at + b[1], "sounds/enemies/gulaThunder.wav", 0.3) end
        end
        if shot.screen == collage then
            for _, p in ipairs(PANELS) do cue(shot.at + p.at + 0.1, "sounds/domain/shing.wav", 0.28) end
        end
        if shot.screen == title then cue(shot.at + SLAM, "sounds/domain/boom.wav", 0.6) end
    end
    table.sort(CUES, function(a, b) return a.at < b.at end)
end

----------------------------------------------------------------------- baking the maps

-- one map, drawn whole into a canvas: { canvas, lights } (or { failed = true })
local function bake(name)
    local ok, map = pcall(sti, "maps/" .. name .. ".lua")
    if not ok or not map then return { failed = true } end
    local w, h = map.width * map.tilewidth, map.height * map.tileheight
    local made, canvas = pcall(love.graphics.newCanvas, w, h)
    if not made or not canvas then return { failed = true } end

    structures:setMap(map)
    forestDecor:setMap(map)
    local realSpawnWall = spawnWall
    spawnWall = function() end -- (just the pictures: no colliders)
    villageDecor:setMap(map, name)
    spawnWall = realSpawnWall

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.clear(0.06, 0.06, 0.07, 1)
    setWhite()
    for _, layer in ipairs(map.layers) do
        if isGroundLayer(layer) then map:drawLayer(layer) end
    end
    structures:drawAll()
    local items = {}
    forestDecor:collect(items)
    villageDecor:collect(items)
    table.sort(items, function(a, b) return a.y < b.y end)
    for _, item in ipairs(items) do item.draw(item.arg) end
    if map.layers["Above"] then map:drawLayer(map.layers["Above"]) end
    love.graphics.setCanvas()
    love.graphics.pop()

    local lights = {}
    if map.layers["Lights"] then
        for _, obj in ipairs(map.layers["Lights"].objects) do
            local props = obj.properties or {}
            local r, g, b = tostring(props.color or ""):match("([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
            table.insert(lights, {
                x = obj.x + (obj.width or 0) / 2, y = obj.y + (obj.height or 0) / 2,
                radius = tonumber(props.radius) or 48,
                color = r and { tonumber(r), tonumber(g), tonumber(b) } or { 1, 0.72, 0.4 },
                flicker = props.flicker ~= false, seed = math.random() * 100,
            })
        end
    end
    return { canvas = canvas, lights = lights }
end

-- the decor modules back on the map the game has loaded
local function restoreDecor()
    structures:setMap(gameMap)
    forestDecor:setMap(gameMap)
    local realSpawnWall = spawnWall
    spawnWall = function() end
    villageDecor:setMap(gameMap, loadedMap)
    spawnWall = realSpawnWall
end

-- a map drawn whole into a canvas, for the title screen's backdrop
-- (src/ui/menu.lua): { canvas, lights } (or { failed = true })
function intro:bakeMap(name)
    local baked = bake(name)
    restoreDecor()
    return baked
end

----------------------------------------------------------------------- running it

local function newFlake(anywhere)
    return { x = math.random(), y = anywhere and math.random() or -0.02, size = 0.4 + math.random() * 0.8,
        speed = 0.02 + math.random() * 0.035, phase = math.random() * 6.3, alpha = 0.12 + math.random() * 0.28 }
end

function intro:play(onDone)
    if self.music then self:stopMusic() end
    self.active = true
    self.onDone = onDone
    self.t = nil -- (the clock starts once the maps are baked)
    self.baked = {}
    self.toBake = 0
    self.ending, self.endTime = nil, nil
    self.skipped = false
    self.cue = 1
    self.fonts = {
        caption = love.graphics.newFont(FONT_FUTURE, math.floor(6 * scale)),
        name = love.graphics.newFont(FONT_MINI, math.floor(14 * scale)),
        sub = love.graphics.newFont(FONT_VT, math.floor(8 * scale)),
        panel = love.graphics.newFont(FONT_MINI, math.floor(5 * scale)),
        title = love.graphics.newFont(FONT_MINI, math.floor(30 * scale)),
        beta = love.graphics.newFont(FONT_FUTURE, math.floor(6 * scale)),
        hint = love.graphics.newFont(FONT_VT, math.floor(5 * scale)),
    }
    self.flakes = {}
    for i = 1, 70 do self.flakes[i] = newFlake(true) end
end

function intro:skip()
    if not self.active then return end
    self.skipped = true
    if not self.t then
        self:finish() -- (still baking: straight on)
        return
    end
    if self.ending then return end
    self.ending, self.endTime = 0, SKIP_FADE
end

function intro:stopMusic()
    self.music:stop()
    self.music:release()
    self.music = nil
end

function intro:finish()
    -- skipped, the music goes with it; played through, it plays on (intro:update)
    if self.music and self.skipped then self:stopMusic() end
    self.tailStart = self.t
    for _, b in pairs(self.baked or {}) do
        if b.canvas then b.canvas:release() end
    end
    self.baked = {}
    restoreDecor()
    self.active = false
    self.fonts = nil
    local done = self.onDone
    self.onDone = nil
    if done then done() end
end

function intro:update(dt)
    if not self.active then
        -- the game has begun: the music plays on, slowly fading out to its end
        if self.music then
            self.t = self.t + dt
            local left = 1 - clamp01((self.t - self.tailStart) / (MUSIC_END - 0.3 - self.tailStart))
            self.music:setVolume(musicLevel() * left * left)
            if left <= 0 or not self.music:isPlaying() then self:stopMusic() end
        end
        return
    end
    -- a map a frame, then the music and the clock start
    if not self.t then
        self.toBake = self.toBake + 1
        local name = MAPS[self.toBake]
        if name then
            self.baked[name] = bake(name)
            return
        end
        restoreDecor()
        local ok, source = pcall(love.audio.newSource, MUSIC, "stream")
        if ok and source then
            self.music = source
            source:setVolume(0)
            source:play()
        end
        self.t = 0
        return
    end

    self.t = self.t + dt
    while CUES[self.cue] and CUES[self.cue].at <= self.t do
        local c = CUES[self.cue]
        if not self.ending then dj.play(c.sound, "static", "effect", c.volume) end
        self.cue = self.cue + 1
    end
    for i, f in ipairs(self.flakes) do
        f.y = f.y + f.speed * dt
        f.x = f.x + math.sin(self.t * 0.7 + f.phase) * 0.006 * dt
        if f.y > 1.03 then self.flakes[i] = newFlake(false) end
    end

    if not self.ending and self.t >= TOTAL - END_FADE then self.ending, self.endTime = 0, END_FADE end
    if self.ending then self.ending = self.ending + dt end
    self.musicVolume = musicLevel() * span(self.t, 0, 0.6)
    if self.music then
        -- (skipped: the music fades with the picture)
        local going = self.skipped and clamp01(self.ending / self.endTime) or 0
        self.music:setVolume(self.musicVolume * (1 - going))
    end
    if self.ending and self.ending >= self.endTime then self:finish() end
end

-- how much a shot shows, lt seconds into it
local function showing(shot, lt)
    local fadeIn = shot.at == 0 and span(lt, 0, FIRST_FADE) or span(lt, 0, shot.gap and 0.6 or FADE)
    local fadeOut = shot.fadeOut and span(shot.len - lt, 0, shot.fadeOut) or 1
    return math.min(fadeIn, fadeOut)
end

local greyShader = nil
local function grey()
    if greyShader == nil then
        local ok, shader = pcall(love.graphics.newShader, [[
            extern number amount;
            vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
                vec4 c = Texel(tex, tc) * color;
                float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
                return vec4(mix(c.rgb, vec3(g), amount), c.a);
            }
        ]])
        greyShader = ok and shader or false
    end
    return greyShader or nil
end

function intro:drawCaption(text, lt, shot, w, h)
    local until_ = shot.freeze and (shot.freeze - 0.3) or (shot.len - FADE)
    local a = span(lt, 0.9, 1.4) * (1 - span(lt, until_ - 0.5, until_))
    if a <= 0 then return end
    local f = self.fonts.caption
    love.graphics.setFont(f)
    local tw = f:getWidth(text)
    local x = w - tw - w * 0.05
    local y = h * (1 - BAR) - f:getHeight() - h * 0.035
    local saved = A
    A = A * a
    outlined(text, x, y, { 1, 0.95, 0.85 }, { 0, 0, 0 }, math.max(1, scale * 0.45))
    love.graphics.setLineWidth(math.max(1, scale * 0.3))
    color(1, 0.84, 0.36, 0.9)
    love.graphics.line(x + tw * (1 - a), y - scale * 1.2, x + tw, y - scale * 1.2)
    A = saved
end

-- the freeze frame's card, ft seconds after the freeze
function intro:drawCard(card, ft, w, h)
    local slide = easeOutBack(span(ft, 0.12, 0.5))
    local fade = span(ft, 0.12, 0.3)
    if fade <= 0 then return end
    local nameFont, subFont = self.fonts.name, self.fonts.sub
    local x = w * 0.07 - (1 - slide) * w * 0.15
    local y = h * 0.665
    local tw = nameFont:getWidth(card.name)
    local saved = A
    A = A * fade
    -- a slanted band of their colour behind the name
    color(card.color[1] * 0.35, card.color[2] * 0.35, card.color[3] * 0.35, 0.75)
    local bh = nameFont:getHeight() * 0.62
    local by = y + nameFont:getHeight() * 0.22
    love.graphics.polygon("fill", x - w * 0.03, by, x + tw + w * 0.04, by, x + tw + w * 0.02, by + bh, x - w * 0.05, by + bh)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.shear(-0.18, 0)
    love.graphics.setFont(nameFont)
    outlined(card.name, 0, 0, { card.color[1], card.color[2], card.color[3] }, { 0, 0, 0 }, math.max(2, scale * 0.8))
    love.graphics.pop()
    A = saved * span(ft, 0.35, 0.6)
    love.graphics.setFont(subFont)
    outlined(card.title, x + w * 0.012, y + nameFont:getHeight() * 0.92, { 1, 1, 1 }, { 0, 0, 0 }, math.max(1, scale * 0.4))
    A = saved
end

function intro:drawShot(shot, lt, w, h)
    if shot.screen then
        shot.screen(self, lt, w, h)
        return
    end
    local baked = self.baked[shot.map] or {}
    local frozen = shot.freeze and lt >= shot.freeze
    local t = frozen and shot.freeze or lt
    local p = smooth(t / shot.len)
    local cx, cy = lerp(shot.cam[1], shot.cam[3], p), lerp(shot.cam[2], shot.cam[4], p)
    local k = lerp(shot.zoom[1], shot.zoom[2], p)
    if frozen then k = k * (1 + 0.05 * easeOutBack(span(lt - shot.freeze, 0, 0.35))) end -- (a punch in)
    local z = scale * k
    local jolt = 0
    for _, hit in ipairs(shot.hits or {}) do
        if t >= hit and t < hit + 0.18 then jolt = (1 - (t - hit) / 0.18) * scale * 1.2 end
    end
    local ox = (noise(math.floor(lt * 60), 3) - 0.5) * jolt
    local oy = (noise(math.floor(lt * 60), 4) - 0.5) * jolt

    local shader = frozen and grey()
    if shader then
        love.graphics.setShader(shader)
        shader:send("amount", 0.85 * span(lt - shot.freeze, 0, GREY_TIME))
    end
    love.graphics.push()
    love.graphics.translate(math.floor(w / 2 - cx * z + ox + 0.5), math.floor(h / 2 - cy * z + oy + 0.5))
    love.graphics.scale(z)
    if baked.canvas then
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(A, A, A, A)
        love.graphics.draw(baked.canvas)
        love.graphics.setBlendMode("alpha")
    end
    if shot.actors then shot.actors(t) end
    if shot.dark then
        local hw, hh = w / z / 2 + 8, h / z / 2 + 8
        darkness(baked, t, cx - hw, cy - hh, cx + hw, cy + hh, shot.dark)
    end
    love.graphics.pop()
    love.graphics.setShader()
    love.graphics.setLineWidth(1)

    if shot.caption then self:drawCaption(shot.caption, lt, shot, w, h) end
    if frozen then
        local ft = lt - shot.freeze
        color(1, 1, 1, 0.55 * (1 - span(ft, 0, 0.25))) -- (the flash as it stops)
        love.graphics.rectangle("fill", 0, 0, w, h)
        if shot.card then self:drawCard(shot.card, ft, w, h) end
    end
end

function intro:draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.origin()
    if self.t then
        for _, shot in ipairs(SHOTS) do
            local lt = self.t - shot.at
            if lt >= 0 and lt < shot.len then
                A = showing(shot, lt)
                self:drawShot(shot, lt, w, h)
            end
        end
        A = 1
        -- ash, drifting down over everything
        for _, f in ipairs(self.flakes) do
            local s = math.max(1, f.size * scale * 0.5)
            love.graphics.setColor(0.86, 0.83, 0.8, f.alpha)
            love.graphics.rectangle("fill", math.floor(f.x * w), math.floor(f.y * h), s, s)
        end
    end
    -- the letterbox, and how to skip
    local bar = math.floor(h * BAR)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, bar)
    love.graphics.rectangle("fill", 0, h - bar, w, bar)
    local hint = self.fonts.hint
    love.graphics.setFont(hint)
    love.graphics.setColor(0.7, 0.68, 0.64, 0.6)
    local text = self.t and "Any key: skip" or "Loading..."
    love.graphics.print(text, w - hint:getWidth(text) - w * 0.03, h - bar / 2 - hint:getHeight() / 2)
    -- fading out at the end (or when skipped)
    if self.ending then
        love.graphics.setColor(0, 0, 0, clamp01(self.ending / self.endTime))
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    setWhite()
end
