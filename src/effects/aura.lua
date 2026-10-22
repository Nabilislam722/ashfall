-- Live lightning around someone (Rick, when he comes to the hero's rescue):
-- little arcs keep snapping off their body, and every so often a bolt forks out
-- of them and strikes the ground nearby. On those frames they flash white,
-- sparks fly from the impact and the room lights up for an instant.
--
--   local a = newAura()
--   a:update(dt)
--   a:surge()                       -- a flare: a strike, and its light swells
--   a.timeScale = 0.35              -- slow motion (1 = normal speed)
--   a:draw(x, y, height, figure)    -- x, y: their feet; height: how tall they
--                                   -- stand; figure() draws them (on a strike it
--                                   -- is drawn white, through a shader)
--   a:drawGlow()                    -- the lightning again, added on top: call it
--                                   -- after a dark map's darkness
--   a:flashing()                    -- 1 right after a strike, fading to 0

local FLICKER = 0.035 -- live bolts jump to new shapes this often
local FLASH = 0.1     -- how long they stay white after a strike
local SPARK_LIFE = 0.3

-- a jagged line from (x1, y1) to (x2, y2), wandering up to `spread` either side
local function jagged(x1, y1, x2, y2, spread, step)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local ux, uy, nx, ny = dx / len, dy / len, -dy / len, dx / len
    local points = { x1, y1 }
    for d = step, len - step, step do
        local off = (math.random() - 0.5) * 2 * spread
        table.insert(points, x1 + ux * d + nx * off)
        table.insert(points, y1 + uy * d + ny * off)
    end
    table.insert(points, x2)
    table.insert(points, y2)
    return points
end

local function color(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], alpha)
end

function newAura(palette)
    local a = { t = 0, bolts = {}, impacts = {}, flash = 0, surging = 0, arcTimer = 0, strikeTimer = 0.3, flicker = 0, height = 24, timeScale = 1 }
    a.palette = palette or {
        glow = { 0.45, 0.75, 1 },  -- the bolts' glow
        core = { 0.92, 0.97, 1 },  -- their white-hot core
        spark = { 0.8, 0.93, 1 },
    }

    -- a point on their body, relative to their feet
    local function bodyPoint(h)
        return (math.random() - 0.5) * h * 0.55, -h * (0.25 + math.random() * 0.65)
    end

    -- a new shape for a live bolt (and its forks)
    local function shape(b)
        b.points = jagged(b.x1, b.y1, b.x2, b.y2, b.spread, b.step)
        b.forks = {}
        for _ = 1, b.forkCount do
            local i = 2 * math.random(1, math.max(1, #b.points / 2 - 1)) - 1
            local fx, fy = b.points[i], b.points[i + 1]
            local angle = math.atan2(b.y2 - b.y1, b.x2 - b.x1) + (math.random() < 0.5 and -1 or 1) * (0.5 + math.random() * 0.7)
            local reach = 4 + math.random() * 7
            table.insert(b.forks, jagged(fx, fy, fx + math.cos(angle) * reach, fy + math.sin(angle) * reach, 1.2, 2.5))
        end
    end

    function a:surge()
        self.surging = 1
        self.strikeTimer = 0
    end

    function a:flashing()
        return self.flash / FLASH
    end

    -- a small arc snapping off their body
    function a:spawnArc()
        local h = self.height
        local x1, y1 = bodyPoint(h)
        local angle = math.atan2(y1 + h * 0.5, x1) + (math.random() - 0.5) * 1.2
        local reach = 6 + math.random() * 12
        local b = { x1 = x1, y1 = y1, x2 = x1 + math.cos(angle) * reach, y2 = y1 + math.sin(angle) * reach,
            life = 0.07 + math.random() * 0.09, spread = 1.8, step = 2.5, forkCount = math.random() < 0.4 and 1 or 0 }
        shape(b)
        table.insert(self.bolts, b)
    end

    -- a bolt out of their body, down into the ground beside them (sometimes two)
    function a:spawnStrike()
        local h = self.height
        local side = math.random() < 0.5 and -1 or 1
        for n = 1, math.random() < 0.35 and 2 or 1 do
            local x1, y1 = bodyPoint(h)
            local s = n == 1 and side or -side
            local tx, ty = s * (8 + math.random() * 16), -2 + math.random() * 8
            local b = { x1 = x1, y1 = y1, x2 = tx, y2 = ty, life = 0.16, spread = 3.5, step = 4, forkCount = 2 }
            shape(b)
            table.insert(self.bolts, b)
            local sparks = {}
            for _ = 1, 7 do
                local angle = -math.pi * (0.1 + math.random() * 0.8)
                local speed = 25 + math.random() * 45
                table.insert(sparks, { vx = math.cos(angle) * speed, vy = math.sin(angle) * speed })
            end
            table.insert(self.impacts, { x = tx, y = ty, t = 0, sparks = sparks })
        end
        self.flash = FLASH
        dj.play("sounds/items/zap.wav", "static", "effect", 0.4 + 0.25 * self.surging, 0.9 + math.random() * 0.2)
    end

    function a:update(dt)
        dt = dt * self.timeScale -- in slow motion the lightning slows down too
        self.t = self.t + dt
        self.surging = math.max(0, self.surging - dt * 0.6)
        self.flash = math.max(0, self.flash - dt)
        self.arcTimer = self.arcTimer - dt
        if self.arcTimer <= 0 then
            self:spawnArc()
            self.arcTimer = 0.03 + math.random() * 0.06
        end
        self.strikeTimer = self.strikeTimer - dt
        if self.strikeTimer <= 0 then
            self:spawnStrike()
            self.strikeTimer = 0.6 + math.random() * 0.7
        end
        self.flicker = self.flicker - dt
        local reshape = self.flicker <= 0
        if reshape then self.flicker = FLICKER end
        for i = #self.bolts, 1, -1 do
            local b = self.bolts[i]
            b.life = b.life - dt
            if b.life <= 0 then
                table.remove(self.bolts, i)
            elseif reshape then
                shape(b)
            end
        end
        for i = #self.impacts, 1, -1 do
            local im = self.impacts[i]
            im.t = im.t + dt
            if im.t >= SPARK_LIFE then table.remove(self.impacts, i) end
        end
    end

    function a:drawLightning(x, y, strength)
        pixelfx.world(function() self:drawBolts(x, y, strength) end)
    end

    function a:drawBolts(x, y, strength)
        local pal = self.palette
        love.graphics.push("all")
        love.graphics.translate(x, y)
        love.graphics.setBlendMode("add")
        love.graphics.setLineJoin("bevel")
        -- where a bolt hits: a flat flash on the ground and sparks flying up
        for _, im in ipairs(self.impacts) do
            local f = 1 - im.t / SPARK_LIFE
            color(pal.glow, 0.6 * f * strength)
            love.graphics.rectangle("fill", im.x - 7 * f, im.y - 0.5, 14 * f, 1)
            color(pal.spark, f * strength)
            for _, s in ipairs(im.sparks) do
                local sx = im.x + s.vx * im.t
                local sy = im.y + s.vy * im.t + 90 * im.t * im.t
                love.graphics.rectangle("fill", sx - 0.5, sy - 0.5, 1, 1)
            end
        end
        -- the bolts: a coloured glow under a white-hot core
        for pass = 1, 2 do
            love.graphics.setLineWidth(pass == 1 and 2.5 or 1)
            for _, b in ipairs(self.bolts) do
                local fade = math.min(1, b.life / 0.05) * strength
                if pass == 1 then color(pal.glow, 0.55 * fade) else color(pal.core, fade) end
                love.graphics.line(b.points)
                for _, fork in ipairs(b.forks) do love.graphics.line(fork) end
            end
        end
        love.graphics.pop()
    end

    function a:draw(x, y, height, figure)
        self.height = height
        self.last = { x = x, y = y, figure = figure }
        love.graphics.push("all")
        if self.flash > 0 then love.graphics.setShader(shaders.whiteout) end
        figure()
        love.graphics.pop()
        self:drawLightning(x, y, 1)
    end

    function a:drawGlow()
        local g = self.last
        if not g then return end
        if self.flash > 0 then
            love.graphics.push("all")
            love.graphics.setShader(shaders.whiteout)
            g.figure()
            love.graphics.pop()
        end
        self:drawLightning(g.x, g.y, 0.9)
    end

    return a
end
