-- Screen effects for Rick's rescue in Gula's lair:
--
-- domainFx:play(sx, sy, cast)  Rick's "Domain Expansion: Absolute Zero", in the
--                        style of Jujutsu Kaisen: an anime cut-in on Rick's eyes
--                        (drawCutIn), then from screen point sx, sy the void
--                        spills over the world like ink: an endless field of ice
--                        light rushing outward past a great snowflake sigil and
--                        drifting shards of ice, where only the figures from
--                        cast() stay, faintly lit and mirrored on black ice. An X
--                        of chains lashes across the screen and the title slams
--                        in (drawChains). Then absolute zero: time stops dead,
--                        frost creeps over the screen and the frozen picture
--                        cracks like glass... until domainFx:stop(). The domain
--                        has its own sound (sounds/domain), heard through the
--                        silence
-- domainFx:voidTime()    seconds since the void opened (negative during the cut-in)
-- domainFx:motion()      how fast time flows in the domain: 1, slowing to 0 at
--                        absolute zero
-- domainFx.FREEZE_AT     the void time when its cold takes hold (Gula freezes)
-- domainFx:silence(on)   cut every sound dead and keep the game silent until
--                        lifted (only the domain itself is heard);
--                        domainFx:stop() lifts it too
-- domainFx:closeEyes()   eyelids close slowly, fluttering like falling asleep
-- domainFx:openEyes()    and open again, slowly
-- domainFx:setEyes(v, s) eyelids drift to v (0 open .. 1 closed) over s seconds
-- domainFx:eyes()        0 = open, 1 = closed
-- domainFx:letterbox(on) black cinema bars slide in from the top and bottom
-- domainFx:frost(on)     a light snowfall: the air turning cold
-- domainFx:shout(text, x, y)  big glowing words floating above someone

domainFx = {}
domainFx.active = false
domainFx.t = 0
domainFx.flow = 0  -- time as it flows inside the domain (it stops at absolute zero)
domainFx.lid = 0
domainFx.lidKeys = nil
domainFx.snow = {}
domainFx.bars = 0
domainFx.barsTarget = 0
domainFx.frosting = false
domainFx.frostAlpha = 0
domainFx.shouts = {}

local BAR_HEIGHT = 0.13   -- share of the screen each cinema bar covers
local BAR_SPEED = 1 / 0.9 -- they take about 0.9 s to slide in
local CUTIN_TIME = 1.0    -- the cut-in on Rick's eyes, before the void opens
local GLINT_AT = 0.42     -- his eyes light up
-- from here on, seconds after the void opens:
local VOID_TIME = 0.7     -- the void spills over the screen
local FREEZE_AT = 0.5     -- its cold takes hold (Gula freezes)
local CHAINS_FROM = 0.45  -- the chains start lashing across...
local CHAINS_LOCK = 1.05  -- ...and lock together in the middle
local TITLE_AT = { 0.75, 1.35 } -- "DOMAIN EXPANSION", then "ABSOLUTE ZERO", slammed in
local ZERO_AT = 2.0       -- absolute zero: time stops dead...
local ZERO_EASE = 0.6     -- ...coming to a halt over this long
local CRACK_AT = 3.1      -- the frozen picture cracks like glass,
local CRACK_STEPS = { 0, 0.045, 0.1, 0.17, 0.27, 0.42 } -- crack after crack (as in shatter.wav)
local CRACK_SPEED = 5     -- how fast the cracks run (screen heights a second)
local EYES = { { 12.5, 28.7 }, { 25.5, 28.7 } } -- Rick's eyes in his portrait (pixels)
local DRONE_VOLUME = 0.7

domainFx.FREEZE_AT = FREEZE_AT

-- the domain's sound (sounds/domain, each file made at the loudness it is
-- heard at): { seconds after play(), sound, volume, pitch }
local CUES = {
    { 0, "swell", 1 },                            -- rising through the cut-in, into...
    { GLINT_AT, "shing", 1 },                     -- (his eyes light up)
    { CUTIN_TIME, "boom", 1 },                    -- ...the void opening: the loudest moment
    { CUTIN_TIME + FREEZE_AT, "freeze", 1 },
    { CUTIN_TIME + TITLE_AT[1], "slam", 0.8, 1.12 },
    { CUTIN_TIME + CHAINS_LOCK, "chains", 1 },
    { CUTIN_TIME + TITLE_AT[2], "slam", 1, 0.85 },
    { CUTIN_TIME + ZERO_AT, "shing", 0.9, 0.6 },  -- absolute zero rings out, deep
    { CUTIN_TIME + CRACK_AT, "shatter", 1 },
}

-- the endless field of light inside the void, rushing outward
local function makeStars()
    local stars = {}
    for _ = 1, 170 do
        table.insert(stars, { angle = math.random() * math.pi * 2, d = math.random(), speed = 0.12 + math.random() * 0.3, size = 0.5 + math.random() })
    end
    return stars
end

-- shards of ice adrift in the void: hexagonal plates, six-pointed stars and splinters
local function makeShards()
    local shards = {}
    for _ = 1, 26 do
        table.insert(shards, {
            angle = math.random() * math.pi * 2, d = 0.08 + math.random() * 0.95, speed = 0.05 + math.random() * 0.1,
            turn = math.random() * math.pi * 2, spin = (math.random() - 0.5) * 1.4,
            size = 0.6 + math.random() * 0.9, kind = math.random(1, 3), phase = math.random() * 40,
        })
    end
    return shards
end

local function makeSnow()
    local w, h = love.graphics.getDimensions()
    local snow = {}
    for i = 1, 90 do
        table.insert(snow, { x = math.random() * w, y = math.random() * h, r = 1 + math.random() * 3, speed = 20 + math.random() * 60, drift = math.random() * 6 })
    end
    return snow
end

-- Frost on the screen, as one mesh: feathery fronds of ice growing in from the
-- edges, thickest in the corners. Every line is a thin quad whose texture
-- coordinates hold how far along the frost it grows (u, in screen heights) and
-- which side of the line it is (v, -1..1), for FROST_SHADER to grow and soften.
local function makeFrost(w, h)
    local unit = math.min(w, h)
    local px = pixelfx.size() -- (it is drawn as pixel art: strands one art pixel wide, a few apart)
    local step = math.max(unit * 0.012, 2.5 * px)
    local stemW, featherW, twigW = px, px, px
    local verts, map = {}, {}
    local function line(x1, y1, b1, x2, y2, b2, width, alpha)
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then return end
        local half = width / 2 + 0.25 * px -- a little more, for the soft edge
        local nx, ny = -dy / length * half, dx / length * half
        local n = #verts
        verts[n + 1] = { x1 + nx, y1 + ny, b1 / unit, 1, 1, 1, 1, alpha }
        verts[n + 2] = { x1 - nx, y1 - ny, b1 / unit, -1, 1, 1, 1, alpha }
        verts[n + 3] = { x2 - nx, y2 - ny, b2 / unit, -1, 1, 1, 1, alpha }
        verts[n + 4] = { x2 + nx, y2 + ny, b2 / unit, 1, 1, 1, 1, alpha }
        local m = #map
        map[m + 1], map[m + 2], map[m + 3], map[m + 4], map[m + 5], map[m + 6] = n + 1, n + 2, n + 3, n + 1, n + 3, n + 4
    end
    -- a frond: a gently curving stem with a feather off each side in turn,
    -- shorter toward the tip, and twigs off the feathers, all at the 60 degrees
    -- ice grows at; now and then a smaller frond forks off it
    local function frond(x, y, angle, length, birth, forks)
        local bend = (math.random() - 0.5) * 0.05
        local side = math.random() < 0.5 and -1 or 1
        local d, last = birth or 0, (birth or 0) + length
        while d < last do
            angle = angle + bend + (math.random() - 0.5) * 0.08
            local nx, ny = x + math.cos(angle) * step, y + math.sin(angle) * step
            line(x, y, d, nx, ny, d + step, stemW, 0.55)
            x, y, d = nx, ny, d + step
            side = -side
            if forks and last - d > step * 4 and math.random() < 0.12 then
                frond(x, y, angle + side * math.pi / 3, (last - d) * 0.6, d)
            end
            local l = length * 0.3 * math.max(0, (last - d) / length) ^ 0.8 * (0.6 + math.random() * 0.5)
            if l > step * 0.5 then
                local a = angle + side * math.pi / 3 * (0.9 + math.random() * 0.2)
                local ca, sa = math.cos(a), math.sin(a)
                line(x, y, d, x + ca * l, y + sa * l, d + l, featherW, 0.45)
                local t, twigSide = step * 0.8, 1
                while t < l * 0.85 do
                    local tx, ty = x + ca * t, y + sa * t
                    local tl = (l - t) * 0.4 * (0.5 + math.random() * 0.6)
                    local ta = a + twigSide * math.pi / 3
                    line(tx, ty, d + t, tx + math.cos(ta) * tl, ty + math.sin(ta) * tl, d + t + tl, twigW, 0.35)
                    twigSide = -twigSide
                    t = t + step * (0.7 + math.random() * 0.5)
                end
            end
        end
    end
    for _, c in ipairs({ { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }) do
        local inward = math.atan2(h / 2 - c[2], w / 2 - c[1])
        for i = 1, 5 do
            frond(c[1], c[2], inward + ((i - 0.5) / 5 - 0.5) * 1.8 + (math.random() - 0.5) * 0.2, unit * (0.16 + math.random() * 0.2), 0, true)
        end
    end
    -- along the edges, at uneven gaps: mostly small fronds, a few long ones
    local function edge(x0, y0, x1, y1, inward)
        local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local s = math.random() * unit * 0.05
        while s < length do
            local f = s / length
            frond(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, inward + (math.random() - 0.5) * 1.4,
                unit * (0.025 + 0.13 * math.random() ^ 2.5), 0, true)
            s = s + unit * (0.035 + math.random() * 0.08)
        end
    end
    edge(0, 0, w, 0, math.pi / 2)
    edge(0, h, w, h, -math.pi / 2)
    edge(0, 0, 0, h, 0)
    edge(w, 0, w, h, math.pi)
    local mesh = love.graphics.newMesh(verts, "triangles", "static")
    mesh:setVertexMap(map)
    return mesh
end

-- grows the frost mesh as far as `frontier` (screen heights along it), with a
-- soft growing tip, and softens the edges of its lines
local FROST_SHADER = [[
extern number frontier;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    float grown = clamp((frontier - uv.x) / 0.02, 0.0, 1.0);
    float edge = 1.0 - smoothstep(0.3, 1.0, abs(uv.y));
    return vec4(color.rgb, color.a * grown * edge);
}
]]
local frostShader -- made the first time the frost is drawn (false if it can't be)

-- Cracks across the frozen picture, from the middle where the chains lock: rays
-- running out (a few at a time), splinters off them, and rings joining them like
-- a web. Each crack starts `at` seconds after the first and runs at CRACK_SPEED.
local function makeCracks(w, h)
    local unit = math.min(w, h)
    local cx, cy = w / 2, h / 2
    local width = math.max(1, scale * 0.3)
    local cracks = {}
    local function jagged(x, y, angle, length, birth)
        local pts, births = { x, y }, { birth }
        local d = 0
        while d < length do
            local step = unit * 0.035 * (0.6 + math.random() * 0.8)
            local a = angle + (math.random() - 0.5) * 0.6
            x, y = x + math.cos(a) * step, y + math.sin(a) * step
            d = d + step
            pts[#pts + 1], pts[#pts + 2] = x, y
            births[#births + 1] = birth + d
        end
        return pts, births
    end
    -- the first point of a ray at least `distance` along it
    local function pointAlong(ray, distance)
        local n = #ray.births
        for i = 1, n do
            if ray.births[i] >= distance then return ray.pts[i * 2 - 1], ray.pts[i * 2], ray.births[i] end
        end
        return ray.pts[n * 2 - 1], ray.pts[n * 2], ray.births[n]
    end
    -- which step of CRACK_STEPS each ray breaks on, shuffled around the circle
    local steps = { 1, 1, 1, 1, 2, 2, 3, 3, 4, 4 }
    for i = #steps, 2, -1 do
        local j = math.random(i)
        steps[i], steps[j] = steps[j], steps[i]
    end
    local rays = {}
    for i = 1, #steps do
        local angle = (i - 1 + (math.random() - 0.5) * 0.6) / #steps * math.pi * 2
        local pts, births = jagged(cx, cy, angle, unit * (0.45 + math.random() * 0.5), 0)
        local ray = { pts = pts, births = births, at = CRACK_STEPS[steps[i]], width = width * (1 + math.random() * 0.5) }
        table.insert(rays, ray)
        table.insert(cracks, ray)
        for _ = 1, math.random(1, 2) do
            local x, y, birth = pointAlong(ray, births[#births] * (0.3 + math.random() * 0.45))
            local side = math.random() < 0.5 and -1 or 1
            local sp, sb = jagged(x, y, angle + side * (0.5 + math.random() * 0.5), unit * (0.05 + math.random() * 0.1), birth)
            table.insert(cracks, { pts = sp, births = sb, at = ray.at, width = width * 0.7 })
        end
    end
    for ring, radius in ipairs({ unit * 0.1, unit * 0.22 }) do
        for i, ray in ipairs(rays) do
            if math.random() < 0.75 then
                local other = rays[i % #rays + 1]
                local x1, y1, b1 = pointAlong(ray, radius * (0.9 + math.random() * 0.2))
                local x2, y2 = pointAlong(other, radius * (0.9 + math.random() * 0.2))
                -- sagging a little toward the middle
                local mx, my = cx + ((x1 + x2) / 2 - cx) * 0.9, cy + ((y1 + y2) / 2 - cy) * 0.9
                local d1 = math.sqrt((mx - x1) ^ 2 + (my - y1) ^ 2)
                local d2 = math.sqrt((x2 - mx) ^ 2 + (y2 - my) ^ 2)
                -- (it can't break before its ray has run out that far)
                local at = math.max(CRACK_STEPS[4 + ring], ray.at + b1 / (CRACK_SPEED * unit))
                table.insert(cracks, { pts = { x1, y1, mx, my, x2, y2 }, births = { 0, d1, d1 + d2 }, at = at, width = width * 0.8 })
            end
        end
    end
    return cracks
end

-- a frame fading from the screen's edges to nothing, `inset` in from them
local function makeVignette(w, h, inset)
    local function corner(x, y, a) return { x, y, 0, 0, 1, 1, 1, a } end
    local mesh = love.graphics.newMesh({
        corner(0, 0, 1), corner(w, 0, 1), corner(w, h, 1), corner(0, h, 1),
        corner(inset, inset, 0), corner(w - inset, inset, 0), corner(w - inset, h - inset, 0), corner(inset, h - inset, 0),
    }, "triangles", "static")
    mesh:setVertexMap(1, 2, 5, 2, 6, 5, 2, 3, 6, 3, 7, 6, 3, 4, 7, 4, 8, 7, 4, 1, 8, 1, 5, 8)
    return mesh
end

-- a line of points (b.pts, with b.births) drawn from its start as far as
-- `frontier` along it
local function drawGrown(b, frontier)
    local pts, births = b.pts, b.births
    local n = #births
    if frontier <= births[1] then return end
    if frontier >= births[n] then
        love.graphics.line(pts)
        return
    end
    local out = {}
    for i = 1, n do
        if births[i] <= frontier then
            out[#out + 1] = pts[i * 2 - 1]
            out[#out + 1] = pts[i * 2]
        else
            local f = (frontier - births[i - 1]) / (births[i] - births[i - 1])
            out[#out + 1] = pts[i * 2 - 3] + (pts[i * 2 - 1] - pts[i * 2 - 3]) * f
            out[#out + 1] = pts[i * 2 - 2] + (pts[i * 2] - pts[i * 2 - 2]) * f
            break
        end
    end
    love.graphics.line(out)
end

function domainFx:letterbox(on)
    self.barsTarget = on and 1 or 0
end

-- true while the cinema bars are showing (the HUD steps aside)
function domainFx:cinematic()
    return self.bars > 0.01
end

function domainFx:frost(on)
    self.frosting = on
    if on and #self.snow == 0 then self.snow = makeSnow() end
end

function domainFx:shout(text, x, y)
    table.insert(self.shouts, { text = text, x = x, y = y, t = 0, life = 3.4 })
    dj.play("sounds/items/manaFull.wav", "static", "effect", 0.8, 0.7)
end

function domainFx:setEyes(target, seconds)
    self.lidKeys = { { seconds, target } }
    self.lidFrom, self.lidTime = self.lid, 0
end

-- cast: a function returning { { draw = function, footY = world y }, ... }
function domainFx:play(sx, sy, cast)
    self.active = true
    self.t = 0
    self.flow = 0
    self.cued = {}
    self.chained, self.opened, self.cracked = false, false, false
    self.slammed = {}
    self.cast = cast
    self.ox, self.oy = sx, sy
    if #self.snow == 0 then self.snow = makeSnow() end
    self.stars = makeStars()
    self.shards = makeShards()
    self.glassW = nil -- fresh frost and cracks
    -- floating words make way for the cut-in
    for _, s in ipairs(self.shouts) do s.life = math.min(s.life, s.t + 0.35) end
end

function domainFx:voidTime()
    return self.t - CUTIN_TIME
end

function domainFx:motion()
    if not self.active then return 1 end
    local p = (self:voidTime() - ZERO_AT) / ZERO_EASE
    if p <= 0 then return 1 end
    if p >= 1 then return 0 end
    return (1 - p) * (1 - p)
end

-- 1 while the hero's eyes are no more than half shut, down to 0 as they close
function domainFx:eyeFade()
    return math.max(0, math.min(1, (1 - self.lid) * 2))
end

function domainFx:stop()
    self.active = false
    self.cast = nil
    self:stopSound()
    self:silence(false)
end

function domainFx:stopSound()
    if self.drone then self.drone:stop() end
    self.drone = nil
    dj.stop("domain")
end

-- Every sound cut dead: whatever is playing stops, and sound effects stay muted
-- until the silence lifts. The domain's own sound (tagged "domain") still plays.
function domainFx:silence(on)
    if on and not self.silent then
        self.silent = true
        self.effectVolume = dj.volumeLevels.effect
        love.audio.stop()
        dj.volumeLevels.effect = 0
    elseif not on and self.silent then
        self.silent = false
        dj.volumeLevels.effect = self.effectVolume
    end
end

-- The domain's hum: it rises after the boom, drops away for a moment at absolute
-- zero, slowing like a tape coming to a stop (it stays lower and colder), and
-- fades as the hero's eyes close.
function domainFx:updateDrone(v, motion)
    if v < 0 then return end
    if self.drone == nil then
        local ok, source = pcall(love.audio.newSource, "sounds/domain/drone.wav", "static")
        self.drone = ok and source or false
        if ok then
            source:setLooping(true)
            source:setVolume(0)
            source:play()
        end
    end
    if not self.drone then return end
    local volume = DRONE_VOLUME * math.min(1, v / 1.5) * self:eyeFade()
    local z = v - ZERO_AT
    if z > 0 then volume = volume * (1 - 0.85 * math.min(1, z / 0.15) * math.exp(-math.max(0, z - 0.15) * 1.4)) end
    self.drone:setVolume(pause.active and 0 or volume)
    self.drone:setPitch(0.8 + 0.2 * motion)
end

-- eyelid keyframes: { seconds to get there, how closed }
function domainFx:closeEyes()
    self.lidKeys = { { 1.3, 0.55 }, { 0.6, 0.35 }, { 1.1, 0.8 }, { 0.5, 0.62 }, { 1.4, 1 } }
    self.lidFrom, self.lidTime = self.lid, 0
end

function domainFx:openEyes()
    self.lidKeys = { { 1.2, 0.55 }, { 0.5, 0.75 }, { 1.4, 0 } }
    self.lidFrom, self.lidTime = self.lid, 0
end

function domainFx:eyes()
    return self.lid
end

function domainFx:blinking()
    return self.lidKeys ~= nil
end

function domainFx:reset()
    self:stopSound()
    self:silence(false)
    self.active = false
    self.cast = nil
    self.lid = 0
    self.lidKeys = nil
    self.bars, self.barsTarget = 0, 0
    self.frosting, self.frostAlpha = false, 0
    self.shouts = {}
end

function domainFx:update(dt)
    -- cinema bars
    if self.bars < self.barsTarget then
        self.bars = math.min(self.barsTarget, self.bars + dt * BAR_SPEED)
    elseif self.bars > self.barsTarget then
        self.bars = math.max(self.barsTarget, self.bars - dt * BAR_SPEED)
    end
    -- floating words
    for i = #self.shouts, 1, -1 do
        local s = self.shouts[i]
        s.t = s.t + dt
        if s.t >= s.life then table.remove(self.shouts, i) end
    end
    -- a light snowfall before the domain
    local frostGoal = (self.frosting and not self.active) and 1 or 0
    self.frostAlpha = self.frostAlpha + (frostGoal - self.frostAlpha) * math.min(1, dt * 1.5)
    local motion = self:motion()
    if self.active then
        local v = self:voidTime()
        for i, cue in ipairs(CUES) do
            if not self.cued[i] and self.t >= cue[1] then
                self.cued[i] = true
                dj.play("sounds/domain/" .. cue[2] .. ".wav", "static", "domain", cue[3], cue[4])
            end
        end
        self:updateDrone(v, motion)
        if not self.opened and v >= 0 then
            self.opened = true
            shake:start(0.5, 3, 0.03)
        end
        for i, at in ipairs(TITLE_AT) do
            if not self.slammed[i] and v >= at then
                self.slammed[i] = true
                shake:start(0.15, i == 2 and 4 or 2.5, 0.02)
            end
        end
        if not self.chained and v >= CHAINS_LOCK then
            self.chained = true
            shake:start(0.3, 4, 0.03)
        end
        if not self.cracked and v >= CRACK_AT then
            self.cracked = true
            shake:start(0.25, 3, 0.02)
        end
        -- the light rushes on, the sigil turns and the shards drift... until time stops
        self.flow = self.flow + dt * motion
        for _, s in ipairs(self.stars) do
            s.d = s.d + dt * motion * s.speed * (0.25 + s.d * 1.6)
            if s.d > 1.1 then
                s.d = math.random() * 0.08
                s.angle = math.random() * math.pi * 2
            end
        end
        for _, s in ipairs(self.shards) do
            s.d = s.d + dt * motion * s.speed * (0.2 + s.d)
            s.turn = s.turn + dt * motion * s.spin
            if s.d > 1.15 then
                s.d = 0.04 + math.random() * 0.06
                s.angle = math.random() * math.pi * 2
            end
        end
    end
    if self.active or self.frostAlpha > 0.01 then
        if self.active then self.t = self.t + dt end
        local h = love.graphics.getHeight()
        for _, s in ipairs(self.snow) do
            s.y = s.y + s.speed * dt * motion
            s.x = s.x + math.sin(self.t * 1.5 + s.drift) * 12 * dt * motion
            if s.y > h + 5 then s.y = -5 end
        end
    end
    if self.lidKeys then
        local key = self.lidKeys[1]
        self.lidTime = self.lidTime + dt
        local p = math.min(1, self.lidTime / key[1])
        local eased = p * p * (3 - 2 * p)
        self.lid = self.lidFrom + (key[2] - self.lidFrom) * eased
        if p >= 1 then
            table.remove(self.lidKeys, 1)
            self.lidFrom, self.lidTime = self.lid, 0
            if #self.lidKeys == 0 then self.lidKeys = nil end
        end
    end
end

-- the light snowfall before the domain, under the HUD
function domainFx:drawFrost()
    if self.active or self.frostAlpha <= 0.01 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.setColor(0.55, 0.75, 1, 0.12 * self.frostAlpha)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.pop()
    -- snowflakes: a pixel each, the bigger ones two
    pixelfx.screen(function()
        local px = pixelfx.size()
        for _, s in ipairs(self.snow) do
            local size = s.r > 2.5 and 2 * px or px
            love.graphics.setColor(1, 1, 1, 0.75 * self.frostAlpha)
            love.graphics.rectangle("fill", s.x, s.y, size, size)
        end
    end)
end

-- the black cinema bars
function domainFx:drawBars()
    if self.bars <= 0.001 then return end
    local w, h = love.graphics.getDimensions()
    local e = self.bars * self.bars * (3 - 2 * self.bars)
    local bar = h * BAR_HEIGHT * e
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, bar)
    love.graphics.rectangle("fill", 0, h - bar, w, bar)
    love.graphics.pop()
end

-- big glowing words above someone's head (screen space, over everything)
function domainFx:drawShouts()
    if #self.shouts == 0 then return end
    love.graphics.push("all")
    local font = fonts.pause1
    love.graphics.setFont(font)
    for _, s in ipairs(self.shouts) do
        local fadeIn = math.min(1, s.t / 0.25)
        local fadeOut = math.min(1, (s.life - s.t) / 0.6)
        local alpha = math.min(fadeIn, fadeOut)
        local sx, sy = cam:cameraCoords(s.x, s.y)
        sy = sy - s.t * scale * 1.5
        local pop = 1 + 0.25 * math.max(0, 1 - s.t / 0.2)
        local typed = s.text:sub(1, math.floor(s.t / 0.045))
        local full = font:getWidth(s.text)
        local fh = font:getHeight()
        local pad = scale * 3
        love.graphics.push()
        love.graphics.translate(sx, sy)
        love.graphics.scale(pop, pop)
        -- glowing plate behind the words
        local pulse = 0.5 + 0.5 * math.sin(s.t * 6)
        love.graphics.setColor(0.04, 0.1, 0.22, 0.75 * alpha)
        love.graphics.rectangle("fill", -full / 2 - pad, -fh / 2 - pad * 0.6, full + pad * 2, fh + pad * 1.2, scale, scale)
        love.graphics.setBlendMode("add")
        love.graphics.setLineWidth(math.max(2, scale * 0.6))
        love.graphics.setColor(0.55, 0.85, 1, (0.5 + 0.4 * pulse) * alpha)
        love.graphics.rectangle("line", -full / 2 - pad, -fh / 2 - pad * 0.6, full + pad * 2, fh + pad * 1.2, scale, scale)
        love.graphics.setColor(0.4, 0.7, 1, 0.18 * alpha)
        love.graphics.rectangle("fill", -full / 2 - pad * 2, -fh / 2 - pad * 1.4, full + pad * 4, fh + pad * 2.8, scale * 2, scale * 2)
        love.graphics.setBlendMode("alpha")
        -- the words, typed out, with a dark outline
        local x0, y0 = -full / 2, -fh / 2
        love.graphics.setColor(0.03, 0.08, 0.18, alpha)
        for ox = -1, 1 do
            for oy = -1, 1 do
                if ox ~= 0 or oy ~= 0 then love.graphics.print(typed, x0 + ox * scale * 0.5, y0 + oy * scale * 0.5) end
            end
        end
        love.graphics.setColor(0.85, 0.96, 1, alpha)
        love.graphics.print(typed, x0, y0)
        love.graphics.pop()
    end
    love.graphics.pop()
end

local function outlined(text, font, x, y, w, color, alpha, outline)
    love.graphics.setFont(font)
    love.graphics.setColor(0.05, 0.12, 0.22, alpha)
    for ox = -1, 1 do
        for oy = -1, 1 do
            if ox ~= 0 or oy ~= 0 then love.graphics.printf(text, x + ox * outline, y + oy * outline, w, "center") end
        end
    end
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.printf(text, x, y, w, "center")
end

local SIGIL_BRANCHES = { { 0.42, 0.12 }, { 0.57, 0.17 }, { 0.72, 0.11 } } -- along each arm: where, how long

-- the great snowflake of the domain: two rings, two hexagons and six feathered
-- arms, with a ring of ticks turning the other way
local function snowflake(r, ticksTurn, ticks)
    love.graphics.circle("line", 0, 0, r, 120)
    love.graphics.circle("line", 0, 0, r * 0.94, 120)
    love.graphics.circle("line", 0, 0, r * 0.86, 6) -- six segments: a hexagon, a corner on each arm
    love.graphics.circle("line", 0, 0, r * 0.12, 40)
    love.graphics.push()
    love.graphics.rotate(math.pi / 6)
    love.graphics.circle("line", 0, 0, r * 0.36, 6)
    love.graphics.pop()
    for i = 0, 5 do
        love.graphics.push()
        love.graphics.rotate(i * math.pi / 3)
        love.graphics.line(r * 0.12, 0, r * 0.86, 0)
        for _, b in ipairs(SIGIL_BRANCHES) do
            local x, l = r * b[1], r * b[2]
            love.graphics.line(x + l * 0.5, -l * 0.87, x, 0, x + l * 0.5, l * 0.87)
        end
        love.graphics.polygon("line", r * 0.86, 0, r * 0.9, -r * 0.025, r * 0.94, 0, r * 0.9, r * 0.025)
        love.graphics.pop()
    end
    if ticks then
        love.graphics.push()
        love.graphics.rotate(ticksTurn)
        for i = 0, 47 do
            local a = i / 48 * math.pi * 2
            local c, s = math.cos(a), math.sin(a)
            local inner = i % 4 == 0 and 0.94 or 0.955
            love.graphics.line(c * r * inner, s * r * inner, c * r * 0.985, s * r * 0.985)
        end
        love.graphics.pop()
    end
end

-- The sigil behind the figures: it swells in with the boom, turns slowly, flares
-- as the title slams in and as time stops, and stays brighter once frozen.
-- (Drawn with additive blending.)
function domainFx:drawSigil(cx, cy, v, w, h)
    local q = math.min(1, v / 0.9) - 1
    local size = 1 + 2.70158 * q * q * q + 1.70158 * q * q -- overshooting a little
    local r = math.min(w, h) * 0.42 * size
    if r <= 1 then return end
    local flare = 0
    for _, at in ipairs(TITLE_AT) do
        if v >= at then flare = flare + 0.6 * math.exp(-(v - at) * 5) end
    end
    if v >= ZERO_AT then flare = flare + 1.4 * math.exp(-(v - ZERO_AT) * 3) end
    local frozen = 1 - self:motion()
    local alpha = math.min(1, v / 0.5) * (0.2 + 0.03 * math.sin(self.flow * 2.2) + 0.12 * frozen + 0.25 * flare)
    local turn = self.flow * 0.16
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(turn)
    -- a soft glow, then the sharp lines
    love.graphics.setLineWidth(math.max(3, scale * 1.6))
    love.graphics.setColor(0.3, 0.6, 1, alpha * 0.3)
    snowflake(r, -turn * 2.2, false)
    love.graphics.setLineWidth(math.max(1, scale * 0.3))
    love.graphics.setColor(0.65, 0.88, 1, alpha)
    snowflake(r, -turn * 2.2, true)
    love.graphics.pop()
end

-- one shard of ice at x, y (radius r), and the light catching it now and then
-- as a four-pointed sparkle. (Drawn with additive blending.)
local function drawShard(s, x, y, r, alpha, glint)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(s.turn)
    if s.kind == 1 then
        -- a hexagonal plate
        love.graphics.setColor(0.5, 0.78, 1, 0.12 * alpha)
        love.graphics.circle("fill", 0, 0, r, 6)
        love.graphics.setColor(0.75, 0.92, 1, 0.7 * alpha)
        love.graphics.circle("line", 0, 0, r, 6)
        love.graphics.line(-r, 0, r, 0)
        love.graphics.line(-r * 0.5, -r * 0.87, r * 0.5, r * 0.87)
        love.graphics.line(-r * 0.5, r * 0.87, r * 0.5, -r * 0.87)
    elseif s.kind == 2 then
        -- a six-pointed star: two triangles
        love.graphics.setColor(0.75, 0.92, 1, 0.65 * alpha)
        love.graphics.circle("line", 0, 0, r, 3)
        love.graphics.rotate(math.pi / 3)
        love.graphics.circle("line", 0, 0, r, 3)
    else
        -- a splinter
        love.graphics.setColor(0.5, 0.78, 1, 0.15 * alpha)
        love.graphics.polygon("fill", -r * 1.6, 0, 0, -r * 0.35, r * 1.6, 0, 0, r * 0.35)
        love.graphics.setColor(0.75, 0.92, 1, 0.7 * alpha)
        love.graphics.polygon("line", -r * 1.6, 0, 0, -r * 0.35, r * 1.6, 0, 0, r * 0.35)
    end
    love.graphics.pop()
    if glint > 0.02 then
        local g = r * (1.2 + 1.8 * glint)
        love.graphics.setColor(1, 1, 1, glint * alpha)
        love.graphics.polygon("fill", x - g, y, x, y - g * 0.12, x + g, y, x, y + g * 0.12)
        love.graphics.polygon("fill", x, y - g, x + g * 0.12, y, x, y + g, x - g * 0.12, y)
    end
end

-- Inside the domain the world is gone: black spreads out from Rick until only
-- the figures in the scene are left, in shadow, with a little cold light on
-- their edges and their reflections on the black ice. Behind them the great
-- snowflake turns and shards of ice drift; at absolute zero it all stops dead
-- and ices over. Drawn right after the world, under everything else.
function domainFx:drawVoid()
    if not self.active then return end
    local v = self:voidTime()
    if v < 0 then return end
    local w, h = love.graphics.getDimensions()
    local reach = math.sqrt(w * w + h * h)
    local grow = math.min(1, v / VOID_TIME)
    -- a little past the far corner, so the wobbling edge clears the screen
    local radius = reach * 1.22 * grow * grow * (3 - 2 * grow)
    local frozen = 1 - self:motion()

    local cx, cy = w / 2, h / 2
    pixelfx.screen(function()
        love.graphics.setColor(0.008, 0.01, 0.025, 1)
        if grow >= 1 then
            love.graphics.rectangle("fill", 0, 0, w, h)
        else
            -- the void spills over the world like ink, its edge wobbling with tendrils
            local edge = {}
            local n = 96
            for i = 0, n do
                local a = i / n * math.pi * 2
                local wobble = 1 + 0.07 * math.sin(a * 5 + v * 3) + 0.05 * math.sin(a * 11 - v * 4) + 0.035 * math.sin(a * 23 + v * 7)
                table.insert(edge, self.ox + math.cos(a) * radius * wobble)
                table.insert(edge, self.oy + math.sin(a) * radius * wobble)
            end
            for i = 1, n * 2, 2 do
                love.graphics.polygon("fill", self.ox, self.oy, edge[i], edge[i + 1], edge[i + 2], edge[i + 3])
            end
            love.graphics.setBlendMode("add")
            love.graphics.setLineWidth(scale * 3)
            love.graphics.setColor(0.55, 0.85, 1, 0.5 * (1 - grow))
            love.graphics.line(edge)
            love.graphics.setBlendMode("alpha")
        end

        -- the endless field of light: streaks rushing out of the centre
        local spin = self.flow * 0.05
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.4, 0.7, 1, 0.07 * grow)
        love.graphics.circle("fill", cx, cy, reach * 0.12)
        for _, s in ipairs(self.stars) do
            local a = s.angle + spin
            local far = s.d * reach * 0.62
            local near = math.max(0, s.d - (0.015 + s.d * 0.13)) * reach * 0.62
            local x2, y2 = cx + math.cos(a) * far, cy + math.sin(a) * far
            if (x2 - self.ox) ^ 2 + (y2 - self.oy) ^ 2 < (radius * 0.85) ^ 2 then
                love.graphics.setLineWidth(math.max(1, s.size * scale * 0.22 * (0.4 + s.d)))
                love.graphics.setColor(0.7, 0.88, 1, math.min(1, s.d * 1.6) * 0.75)
                love.graphics.line(cx + math.cos(a) * near, cy + math.sin(a) * near, x2, y2)
            end
        end
        self:drawSigil(cx, cy, v, w, h)
        -- shards of ice adrift in the dark
        love.graphics.setLineWidth(math.max(1, scale * 0.22))
        for _, s in ipairs(self.shards) do
            local far = s.d * reach * 0.62
            local x, y = cx + math.cos(s.angle) * far, cy + math.sin(s.angle) * far
            if (x - self.ox) ^ 2 + (y - self.oy) ^ 2 < (radius * 0.85) ^ 2 then
                local glint = math.max(0, math.sin(self.t * 1.3 + s.phase)) ^ 40
                drawShard(s, x, y, scale * s.size * (0.8 + s.d * 3), math.min(1, s.d * 4) * grow, glint)
            end
        end
        love.graphics.setBlendMode("alpha")

        -- motes of ice drifting in the dark: a pixel each
        local px = pixelfx.size()
        for _, m in ipairs(self.snow) do
            love.graphics.setColor(0.75, 0.88, 1, 0.45 * grow)
            love.graphics.rectangle("fill", m.x, m.y, px, px)
        end
    end)

    love.graphics.push("all")
    local cast = self.cast and self.cast() or {}
    if #cast > 0 then
        if not self.figures or self.figures:getWidth() ~= w or self.figures:getHeight() ~= h then
            self.figures = love.graphics.newCanvas(w, h)
            self.mirror = love.graphics.newCanvas(w, h)
        end
        local target = love.graphics.getCanvas()
        love.graphics.setCanvas(self.figures)
        love.graphics.clear(0, 0, 0, 0)
        cam:attach()
        for _, c in ipairs(cast) do c.draw() end
        cam:detach()
        -- the same figures, upside down below their feet
        love.graphics.setCanvas(self.mirror)
        love.graphics.clear(0, 0, 0, 0)
        cam:attach()
        for _, c in ipairs(cast) do
            love.graphics.push()
            love.graphics.translate(0, c.footY * 2)
            love.graphics.scale(1, -1)
            c.draw()
            love.graphics.pop()
        end
        cam:detach()
        love.graphics.setCanvas(target)

        love.graphics.setColor(0.45, 0.65, 1, 0.16 * grow)
        love.graphics.draw(self.mirror, 0, 0)
        -- (frozen, they turn a little paler and colder)
        love.graphics.setColor(0.36 + 0.1 * frozen, 0.42 + 0.14 * frozen, 0.56 + 0.2 * frozen, grow)
        love.graphics.draw(self.figures, 0, 0)
        -- cold light catching their edges
        local rim = math.max(1, getRenderScale() * 0.8)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.35, 0.65, 1, (0.3 + 0.25 * frozen) * grow)
        love.graphics.draw(self.figures, -rim, -rim)
        love.graphics.setBlendMode("alpha")
    end
    -- at absolute zero the whole picture ices over
    if frozen > 0 then
        love.graphics.setColor(0.6, 0.8, 1, 0.06 * frozen)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    love.graphics.pop()
end

-- the anime cut-in before the void opens: a panel across the screen with
-- speed lines rushing past a close-up of Rick's eyes, which light up; then the
-- panel whites out and the domain opens
function domainFx:drawCutIn()
    if not self.active or self.t >= CUTIN_TIME then return end
    local w, h = love.graphics.getDimensions()
    local t = self.t
    local open = math.min(1, t / 0.12)
    local band = h * 0.27 * open
    local cy = h * 0.5
    local top = cy - band / 2
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.5 * open)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setScissor(0, math.floor(top), w, math.ceil(band))
    love.graphics.setColor(0.02, 0.05, 0.12, 1)
    love.graphics.rectangle("fill", 0, top, w, band)

    -- Rick's eyes, close up, pushing in slowly
    local img = sprites.enemies.rickPortrait
    local s = w * 0.6 / img:getWidth() * (1 + 0.07 * t)
    local slide = w * 0.06 * (1 - math.min(1, t / 0.35)) ^ 2
    local x = w / 2 + slide
    local eyeY = EYES[1][2]
    love.graphics.setColor(0.72, 0.84, 1, 1)
    love.graphics.draw(img, x, cy, 0, s, s, img:getWidth() / 2, eyeY)

    love.graphics.setScissor()
    love.graphics.pop()

    pixelfx.screen(function()
        local px = pixelfx.size()
        love.graphics.setScissor(0, math.floor(top / px), math.ceil(w / px) + 1, math.ceil(band / px))
        -- speed lines rushing past
        love.graphics.setBlendMode("add")
        for i = 1, 28 do
            local seed = i * 97.31
            local y = top + band * ((seed * 0.613) % 1)
            local length = w * (0.12 + (seed * 0.371) % 0.3)
            local lx = (w * ((seed * 0.217) % 1) - t * w * 2.6) % (w + length) - length
            love.graphics.setColor(0.6, 0.85, 1, 0.18 + 0.3 * ((seed * 0.53) % 1))
            love.graphics.rectangle("fill", lx, y, length, px)
        end

        -- the eyes light up: an icy glint, a flare across each one with a sparkle,
        -- and a ripple of cold light
        if t >= GLINT_AT then
            local glint = math.min(1, (t - GLINT_AT) / 0.12)
            local ping = math.min(1, (t - GLINT_AT) / 0.25)
            local pulse = 0.85 + 0.15 * math.sin(t * 40)
            for _, e in ipairs(EYES) do
                local ex = x + (e[1] - img:getWidth() / 2) * s
                local ey = cy + (e[2] - eyeY) * s
                love.graphics.setColor(0.3, 0.7, 1, 0.35 * glint)
                love.graphics.circle("fill", ex, ey, s * 3.2 * pulse)
                love.graphics.setColor(0.7, 0.95, 1, 0.9 * glint)
                love.graphics.circle("fill", ex, ey, s * 1.1)
                love.graphics.setColor(1, 1, 1, glint)
                love.graphics.circle("fill", ex, ey, s * 0.45)
                love.graphics.setColor(0.6, 0.9, 1, 0.55 * glint)
                love.graphics.rectangle("fill", ex - w * 0.16 * glint, ey - s * 0.12, w * 0.32 * glint, s * 0.24)
                local ray, thin = s * 2.6 * glint, s * 0.14
                love.graphics.setColor(0.85, 0.97, 1, 0.8 * glint)
                love.graphics.polygon("fill", ex - ray, ey, ex, ey - thin, ex + ray, ey, ex, ey + thin)
                love.graphics.polygon("fill", ex, ey - ray * 0.8, ex + thin, ey, ex, ey + ray * 0.8, ex - thin, ey)
                if ping < 1 then
                    love.graphics.setLineWidth(math.max(1, s * 0.12))
                    love.graphics.setColor(0.7, 0.92, 1, 0.5 * (1 - ping) ^ 2)
                    love.graphics.circle("line", ex, ey, s * (1 + 6 * ping))
                end
            end
        end
        love.graphics.setBlendMode("alpha")

        -- sharp panel edges
        love.graphics.setScissor()
        love.graphics.setColor(0.85, 0.95, 1, open)
        love.graphics.rectangle("fill", 0, top - px, w, px)
        love.graphics.rectangle("fill", 0, top + band, w, px)
    end)

    -- the white-out into the domain
    love.graphics.push("all")
    local white = math.max(0, (t - (CUTIN_TIME - 0.16)) / 0.16)
    if white > 0 then
        love.graphics.setColor(1, 1, 1, white)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    love.graphics.pop()
end

-- one chain from (x0, y0) toward (x1, y1), as far as `progress` (0..1)
local function drawChain(x0, y0, x1, y1, progress, jitter)
    local dx, dy = x1 - x0, y1 - y0
    local length = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / length, dy / length
    local angle = math.atan2(dy, dx)
    local link = scale * 7
    local count = math.floor(length * progress / (link * 0.8))
    for i = 0, count - 1 do
        local d = (i + 0.5) * link * 0.8
        local cx = x0 + ux * d + (math.random() - 0.5) * jitter
        local cy = y0 + uy * d + (math.random() - 0.5) * jitter
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.rotate(angle)
        if i % 2 == 0 then
            -- a link seen face-on: a steel ring
            love.graphics.setColor(0.03, 0.05, 0.09, 1)
            love.graphics.setLineWidth(math.max(3, scale * 1.7))
            love.graphics.ellipse("line", 0, 0, link * 0.55, link * 0.3)
            love.graphics.setColor(0.7, 0.8, 0.92, 1)
            love.graphics.setLineWidth(math.max(2, scale * 0.8))
            love.graphics.ellipse("line", 0, 0, link * 0.55, link * 0.3)
            love.graphics.setColor(1, 1, 1, 0.85)
            love.graphics.setLineWidth(math.max(1, scale * 0.35))
            love.graphics.line(-link * 0.32, -link * 0.24, link * 0.08, -link * 0.29)
        else
            -- a link seen edge-on: a bar
            love.graphics.setColor(0.03, 0.05, 0.09, 1)
            love.graphics.rectangle("fill", -link * 0.6, -link * 0.13, link * 1.2, link * 0.26, link * 0.13, link * 0.13)
            love.graphics.setColor(0.6, 0.71, 0.85, 1)
            love.graphics.rectangle("fill", -link * 0.54, -link * 0.07, link * 1.08, link * 0.14, link * 0.07, link * 0.07)
        end
        love.graphics.pop()
    end
end

-- how far the frost has crept (0..1): a first rim of it at the edges as the
-- domain opens, then racing in at absolute zero
local function frostGrowth(v)
    if v < 0.3 then return 0 end
    if v < ZERO_AT then
        local p = (v - 0.3) / (ZERO_AT - 0.3)
        return 0.1 * p * p * (3 - 2 * p)
    end
    local p = math.min(1, (v - ZERO_AT) / 1.1)
    return 0.1 + 0.9 * (1 - (1 - p) ^ 3)
end

-- frost and cracks on the glass of the screen, over everything; they fade as
-- the hero's eyes close
function domainFx:drawGlass(v, w, h)
    local fade = self:eyeFade()
    if fade <= 0.01 then return end
    if self.glassW ~= w or self.glassH ~= h then
        self.glassW, self.glassH = w, h
        self.frostMesh = makeFrost(w, h)
        self.cracks = makeCracks(w, h)
        self.rime = makeVignette(w, h, math.min(w, h) * 0.07)
    end
    if frostShader == nil then
        local ok, shader = pcall(love.graphics.newShader, FROST_SHADER)
        frostShader = ok and shader or false
    end
    local unit = math.min(w, h)
    local grown = frostGrowth(v)
    if grown > 0 then
        -- a band of rime along the edges, and the frost growing in from it
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.6, 0.8, 1, 0.22 * math.min(1, grown * 3) * fade)
        love.graphics.draw(self.rime)
        if frostShader then
            frostShader:send("frontier", grown * 0.42)
            love.graphics.setShader(frostShader)
            love.graphics.setColor(0.85, 0.94, 1, fade)
            love.graphics.draw(self.frostMesh)
            love.graphics.setShader()
        end
        love.graphics.setBlendMode("alpha")
    end
    local since = v - CRACK_AT
    if since >= 0 then
        local speed = CRACK_SPEED * unit
        -- each crack a dark edge with a bright one on top
        love.graphics.setColor(0.01, 0.03, 0.07, 0.6 * fade)
        for _, c in ipairs(self.cracks) do
            love.graphics.setLineWidth(c.width * 2.4)
            drawGrown(c, (since - c.at) * speed)
        end
        love.graphics.setColor(0.88, 0.96, 1, 0.95 * fade)
        for _, c in ipairs(self.cracks) do
            love.graphics.setLineWidth(c.width)
            drawGrown(c, (since - c.at) * speed)
        end
        -- a soft burst of white where it breaks
        local burst = 1 - since / 0.3
        if burst > 0 then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0.85, 0.95, 1, 0.22 * burst * fade)
            local r = scale * (3 + 12 * (1 - burst))
            for i = 1, 5 do love.graphics.circle("fill", w / 2, h / 2, r * i / 5) end
            love.graphics.setBlendMode("alpha")
        end
    end
end

-- an X of chains lashing across the whole screen, over the eyelids and the
-- bars, the title card on top, and over it all the frost and the cracks
function domainFx:drawChains()
    if not self.active then return end
    local t = self:voidTime()
    if t < 0 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    local chains = math.min(1, math.max(0, (t - CHAINS_FROM) / (CHAINS_LOCK - CHAINS_FROM)))
    if chains > 0 then
        local reach = 1 - (1 - chains) ^ 2
        local jitter = (t >= CHAINS_LOCK and t < CHAINS_LOCK + 0.3) and scale * 1.2 or 0
        local m = scale * 6
        pixelfx.screen(function()
            -- a frosty glow along each chain
            love.graphics.setBlendMode("add")
            love.graphics.setLineWidth(scale * 6)
            love.graphics.setColor(0.35, 0.65, 1, 0.14)
            love.graphics.line(-m, -m, -m + (w + m * 2) * reach, -m + (h + m * 2) * reach)
            love.graphics.line(w + m, -m, w + m - (w + m * 2) * reach, -m + (h + m * 2) * reach)
            love.graphics.setBlendMode("alpha")
            drawChain(-m, -m, w + m, h + m, reach, jitter)
            drawChain(w + m, -m, -m, h + m, reach, jitter)
            -- a burst of frost where they lock
            if t >= CHAINS_LOCK then
                local burst = math.min(1, (t - CHAINS_LOCK) / 0.5)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(0.7, 0.9, 1, 0.7 * (1 - burst))
                love.graphics.circle("fill", w / 2, h / 2, scale * (6 + 18 * burst))
                love.graphics.setBlendMode("alpha")
            end
        end)

        -- the title, slammed in over the chains one line at a time: it lands
        -- big, with its colours split apart, and settles
        local function slam(text, font, y, at, color, outline)
            local since = t - at
            if since <= 0 then return end
            local landed = math.min(1, since / 0.16)
            local zoom = 1 + 1.1 * (1 - landed) ^ 2
            local split = scale * 3.5 * math.max(0, 1 - since / 0.55)
            local mid = y + font:getHeight() / 2
            love.graphics.push()
            love.graphics.translate(w / 2, mid)
            love.graphics.scale(zoom)
            love.graphics.translate(-w / 2, -mid)
            if split > 0.3 then
                love.graphics.setFont(font)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(0, 0.8, 1, 0.7 * landed)
                love.graphics.printf(text, -split, y, w, "center")
                love.graphics.setColor(1, 0.2, 0.45, 0.7 * landed)
                love.graphics.printf(text, split, y, w, "center")
                love.graphics.setBlendMode("alpha")
            end
            outlined(text, font, 0, y, w, color, landed, outline)
            love.graphics.pop()
        end
        local y = h * 0.26
        slam("DOMAIN EXPANSION", fonts.vsName, y, TITLE_AT[1], { 0.85, 0.95, 1 }, math.max(2, scale * 0.5))
        slam("ABSOLUTE ZERO", fonts.vs, y + fonts.vsName:getHeight() * 1.1, TITLE_AT[2], { 0.75, 0.92, 1 }, math.max(3, scale * 0.9))
    end
    pixelfx.screen(function() self:drawGlass(t, w, h) end)
    love.graphics.pop()
end

-- over the HUD: the white flash as the domain opens, and at absolute zero a
-- cold flash with a ring of frost racing out from Rick
function domainFx:draw()
    if not self.active then return end
    local v = self:voidTime()
    if v < 0 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    if v < 0.25 then
        love.graphics.setColor(1, 1, 1, 0.85 * (1 - v / 0.25))
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    local z = v - ZERO_AT
    if z >= 0 and z < 1 then
        if z < 0.3 then
            love.graphics.setColor(0.75, 0.9, 1, 0.4 * (1 - z / 0.3))
            love.graphics.rectangle("fill", 0, 0, w, h)
        end
        local ring = math.sqrt(w * w + h * h) * (1 - (1 - z) ^ 3)
        pixelfx.screen(function()
            love.graphics.setBlendMode("add")
            love.graphics.setLineWidth(scale * (0.5 + 4 * (1 - z)))
            love.graphics.setColor(0.6, 0.85, 1, 0.75 * (1 - z))
            love.graphics.circle("line", self.ox, self.oy, ring, 120)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1, 0.9 * (1 - z))
            love.graphics.circle("line", self.ox, self.oy, ring * 0.97, 120)
        end)
    end
    love.graphics.pop()
end

-- eyelids, over everything
function domainFx:drawEyes()
    if self.lid <= 0.001 then return end
    local w, h = love.graphics.getDimensions()
    local lid = self.lid
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.35 * lid)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(0.02, 0.01, 0.02, 1)
    if lid >= 0.999 then
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.pop()
        return
    end
    love.graphics.pop()
    -- each lid's rim arches away from the middle, so the opening is a lens shape
    pixelfx.screen(function()
        love.graphics.setColor(0.02, 0.01, 0.02, 1)
        local edge = (h / 2) * lid * 1.15
        local curve = h * 0.14 * math.min(1, lid * 2)
        local segments = 32
        for _, side in ipairs({ -1, 1 }) do
            local verts = {}
            for i = 0, segments do
                local x = w * i / segments
                local t = (x - w / 2) / (w / 2)
                local depth = edge - curve * (1 - t * t)
                table.insert(verts, x)
                table.insert(verts, side < 0 and depth or h - depth)
            end
            table.insert(verts, w)
            table.insert(verts, side < 0 and -1 or h + 1)
            table.insert(verts, 0)
            table.insert(verts, side < 0 and -1 or h + 1)
            local ok, triangles = pcall(love.math.triangulate, verts)
            if ok then
                for _, tri in ipairs(triangles) do love.graphics.polygon("fill", tri) end
            end
        end
    end)
end
