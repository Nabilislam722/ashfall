-- The "VS" banner shown when a boss fight starts: the player slides in from
-- the left, the boss from the right, and "VS" slams down in the middle.
--
-- vsBanner:play(leftCard, rightCard)
--   card = { image = Image, quad = Quad (optional), name = "RICK",
--            title = "The Food Thief", color = {r, g, b}, glow = {r, g, b} }
--
-- Runs for about 2.5 seconds; any key or click skips it once "VS" is down.
-- Inside a cutscene, use cutscene:versus(leftCard, rightCard) to wait for it.

vsBanner = {}
vsBanner.active = false

local OPEN_TIME = 0.25    -- band opens
local SLIDE_START = 0.12  -- fighters start sliding in
local SLIDE_TIME = 0.42
local VS_TIME = 0.55      -- "VS" slams down
local VS_DROP = 0.16
local HOLD_UNTIL = 2.35   -- starts leaving on its own
local EXIT_TIME = 0.35
local SKIP_AFTER = 0.4

local GOLD = {0.98, 0.84, 0.36}

local function clamp01(v) return math.max(0, math.min(1, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOutQuad(t) return 1 - (1 - t) * (1 - t) end
local function easeInQuad(t) return t * t end
local function easeOutBack(t)
    local c1, c3 = 1.6, 2.6
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function vsBanner:play(left, right)
    self.active = true
    self.left, self.right = left, right
    self.t = 0
    self.exitT = nil
    self.flash = 0
    self.slammed = false
    self.whooshed = false
end

function vsBanner:skip()
    if self.active and not self.exitT and self.t >= SKIP_AFTER then
        self.exitT = 0
    end
end

function vsBanner:reset()
    self.active = false
    self.left, self.right = nil, nil
end

function vsBanner:update(dt)
    if not self.active then return end
    self.t = self.t + dt
    self.flash = math.max(0, self.flash - dt * 3.5)

    if not self.whooshed and self.t >= SLIDE_START then
        self.whooshed = true
        dj.play(sounds.items.sword, "static", "effect", 0.9, 0.6)
    end
    if not self.slammed and self.t >= VS_TIME + VS_DROP then
        self.slammed = true
        self.flash = 1
        shake:start(0.3, 3, 0.03)
        dj.play(sounds.items.explosion, "static", "effect", 0.7, 0.7)
    end

    if not self.exitT and self.t >= HOLD_UNTIL then
        self.exitT = 0
    end
    if self.exitT then
        self.exitT = self.exitT + dt
        if self.exitT >= EXIT_TIME then
            self:reset()
        end
    end
end

-- outlined text, centered on x
local function printOutlined(text, font, x, y, color, alpha, outline)
    love.graphics.setFont(font)
    local w = font:getWidth(text)
    love.graphics.setColor(0, 0, 0, alpha)
    for ox = -1, 1 do
        for oy = -1, 1 do
            if ox ~= 0 or oy ~= 0 then
                love.graphics.print(text, x - w / 2 + ox * outline, y + oy * outline)
            end
        end
    end
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.print(text, x - w / 2, y)
end

local function star(cx, cy, outer, inner, points, rotation)
    local verts = {}
    for i = 0, points * 2 - 1 do
        local r = (i % 2 == 0) and outer or inner
        local a = rotation + i * math.pi / points
        table.insert(verts, cx + math.cos(a) * r)
        table.insert(verts, cy + math.sin(a) * r)
    end
    -- triangle fan from the center, so the concave star draws correctly
    for i = 1, #verts, 2 do
        local j = (i + 2 > #verts) and 1 or i + 2
        love.graphics.polygon("fill", cx, cy, verts[i], verts[i + 1], verts[j], verts[j + 1])
    end
end

local function drawFighter(card, x, y, maxH, alpha, bob)
    local image = card.image
    local sw, sh
    if card.quad then
        local _, _, qw, qh = card.quad:getViewport()
        sw, sh = qw, qh
    else
        sw, sh = image:getDimensions()
    end
    local s = math.max(1, math.floor(maxH / sh)) -- whole pixels keep the pixel art crisp
    local dx, dy = math.floor(x - sw * s / 2), math.floor(y - sh * s / 2 + bob)
    local shadow = math.max(2, math.floor(s * 0.6))

    love.graphics.setColor(0, 0, 0, 0.45 * alpha)
    if card.quad then
        love.graphics.draw(image, card.quad, dx + shadow, dy + shadow, 0, s, s)
    else
        love.graphics.draw(image, dx + shadow, dy + shadow, 0, s, s)
    end
    love.graphics.setColor(1, 1, 1, alpha)
    if card.quad then
        love.graphics.draw(image, card.quad, dx, dy, 0, s, s)
    else
        love.graphics.draw(image, dx, dy, 0, s, s)
    end
    return dy + sh * s
end

function vsBanner:draw()
    if not self.active then return end
    local w, h = love.graphics.getDimensions()
    local hs = scale
    local t = self.t
    local exit = self.exitT and easeInQuad(clamp01(self.exitT / EXIT_TIME)) or 0

    local open = easeOutQuad(clamp01(t / OPEN_TIME)) * (1 - exit)
    local fullH = h * 0.44
    local cy = h * 0.46
    local bandH = fullH * open
    local top, bottom = cy - bandH / 2, cy + bandH / 2
    local skew = h * 0.07
    local function seamX(y) return w / 2 - skew * (y - cy) / (fullH / 2) end

    love.graphics.push("all")

    -- dim the world
    love.graphics.setColor(0, 0, 0, 0.55 * open)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if bandH > 1 then
        -- the two halves of the band, split by a slanted seam
        local lc, rc = self.left.color, self.right.color
        love.graphics.setColor(lc[1], lc[2], lc[3], 0.96)
        love.graphics.polygon("fill", 0, top, seamX(top), top, seamX(bottom), bottom, 0, bottom)
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.96)
        love.graphics.polygon("fill", seamX(top), top, w, top, w, bottom, seamX(bottom), bottom)

        -- a lighter stripe through the middle
        local st, sb = cy - bandH * 0.2, cy + bandH * 0.2
        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.polygon("fill", 0, st, seamX(st), st, seamX(sb), sb, 0, sb)
        love.graphics.polygon("fill", seamX(st), st, w, st, w, sb, seamX(sb), sb)

        -- speed lines rushing toward the middle
        for i = 1, 12 do
            local ly = top + bandH * ((i * 0.618) % 1)
            local len = w * (0.06 + ((i * 0.37) % 1) * 0.12)
            local speed = w * (1.0 + ((i * 0.53) % 1) * 0.9)
            local sx = seamX(ly)
            love.graphics.setColor(1, 1, 1, 0.08 + (i % 3) * 0.04)
            local th = math.max(2, hs * (0.5 + (i % 3) * 0.35))
            -- left half: moving right
            local x1 = ((t * speed + i * w * 0.21) % (sx + len)) - len
            local a, b = math.max(0, x1), math.min(sx, x1 + len)
            if b > a then love.graphics.rectangle("fill", a, ly, b - a, th) end
            -- right half: moving left
            local span = w - sx
            local x2 = w - ((t * speed + i * w * 0.17) % (span + len))
            a, b = math.max(sx, x2), math.min(w, x2 + len)
            if b > a then love.graphics.rectangle("fill", a, ly + th * 2, b - a, th) end
        end

        -- gold edges
        local edge = math.max(2, math.floor(hs * 0.8))
        love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 1)
        love.graphics.rectangle("fill", 0, top - edge, w, edge)
        love.graphics.rectangle("fill", 0, bottom, w, edge)
    end

    -- fighters slide in, then bob a little
    local slide = easeOutBack(clamp01((t - SLIDE_START) / SLIDE_TIME))
    local away = w * 0.65 * exit
    local alpha = clamp01((t - SLIDE_START) / 0.12) * (1 - exit)
    local bob = math.sin(t * 3) * hs * 0.6
    local fighterY = cy - fullH * 0.08
    local fighters = {
        { card = self.left, x = lerp(-w * 0.25, w * 0.25, slide) - away, bob = bob },
        { card = self.right, x = lerp(w * 1.25, w * 0.75, slide) + away, bob = -bob },
    }
    -- fighters and names stay inside the band while it opens and closes
    love.graphics.setScissor(0, math.max(0, math.floor(top)), w, math.max(0, math.ceil(bandH)))
    for _, f in ipairs(fighters) do
        local glow = f.card.glow
        for k = 1, 5 do
            love.graphics.setColor(glow[1], glow[2], glow[3], 0.07 * alpha)
            love.graphics.circle("fill", f.x, fighterY, fullH * (0.46 - k * 0.06) * open)
        end
    end
    for _, f in ipairs(fighters) do
        local feet = drawFighter(f.card, f.x, fighterY, fullH * 0.64, alpha, f.bob)
        local nameY = math.max(feet + hs * 1.5, cy + fullH * 0.2)
        printOutlined(f.card.name, fonts.vsName, f.x, nameY, GOLD, alpha, math.max(2, hs * 0.5))
        if f.card.title then
            printOutlined(f.card.title, fonts.vsTitle, f.x, nameY + fonts.vsName:getHeight() * 1.05,
                {0.96, 0.92, 0.85}, alpha, math.max(1, hs * 0.35))
        end
    end
    love.graphics.setScissor()

    -- "VS" slams down on a burst
    local drop = clamp01((t - VS_TIME) / VS_DROP)
    if drop > 0 then
        local vsAlpha = drop * (1 - exit)
        local size = lerp(2.8, 1, easeOutQuad(drop))
        if self.slammed then
            -- bright seam
            love.graphics.setColor(1, 1, 1, 0.9 * (1 - exit))
            love.graphics.setLineWidth(math.max(2, hs * 0.9))
            love.graphics.line(seamX(top), top, seamX(bottom), bottom)
            -- burst behind the letters
            local pop = 1 + math.max(0, self.flash) * 0.25
            local r = fullH * 0.3 * pop * (1 - exit)
            love.graphics.setColor(1, 0.45, 0.08, 0.95 * vsAlpha)
            star(w / 2, cy, r, r * 0.62, 14, t * 0.6)
            love.graphics.setColor(1, 0.85, 0.35, 0.95 * vsAlpha)
            star(w / 2, cy, r * 0.72, r * 0.5, 14, -t * 0.8)
        end
        love.graphics.push()
        love.graphics.translate(w / 2, cy)
        love.graphics.rotate(-0.08)
        love.graphics.scale(size, size)
        local fh = fonts.vs:getHeight()
        printOutlined("VS", fonts.vs, 0, -fh / 2, {1, 1, 1}, vsAlpha, math.max(3, hs * 0.9))
        -- lower half of the letters in red
        love.graphics.setScissor(0, math.floor(cy + fh * size * 0.04), w, h)
        love.graphics.setColor(1, 0.3, 0.16, vsAlpha)
        love.graphics.print("VS", -fonts.vs:getWidth("VS") / 2, -fh / 2)
        love.graphics.setScissor()
        love.graphics.pop()
    end

    -- white flash on impact
    if self.flash > 0 then
        love.graphics.setColor(1, 1, 1, self.flash * 0.45)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    love.graphics.pop()
end
