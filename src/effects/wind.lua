-- Wind. From the second day on it blows across the outdoors, west to east, and
-- comes and goes in gusts: wisps of air stream past, leaves tumble along, trees
-- sway (src/levels/villageDecor.lua) and the windmill's sails turn. It makes no
-- sound. It came up from Gula's lair, and stops once Gula is frozen.
-- wind.strength (0..1) says how hard it is blowing right now.

wind = {}
wind.strength = 0
wind.gust = 0
wind.t = 0
wind.wisps = {}
wind.leaves = {}

local GUST_EVERY = { 5, 11 } -- seconds between gusts
local LEAF_COLORS = { { 0.45, 0.68, 0.28 }, { 0.6, 0.76, 0.3 }, { 0.82, 0.62, 0.24 }, { 0.72, 0.42, 0.2 } }

wind.gustTimer = 4

-- is the wind blowing where the player is?
function wind:blowing()
    return gamestate == 1 and data.day >= 2 and not data.story.gulaFrozen and worldClock:outdoors()
end

-- the part of the world on screen (with a margin)
local function view(margin)
    local s = getRenderScale()
    local w, h = love.graphics.getWidth() / s, love.graphics.getHeight() / s
    return cam.x - w / 2 - margin, cam.y - h / 2 - margin, w + margin * 2, h + margin * 2
end

function wind:update(dt)
    self.t = self.t + dt
    -- gusts: every few seconds the wind swells for a while, then eases off
    self.gustTimer = self.gustTimer - dt
    if self.gustTimer <= 0 then
        self.gustTimer = GUST_EVERY[1] + math.random() * (GUST_EVERY[2] - GUST_EVERY[1])
        self.gustLeft = 2 + math.random() * 2
    end
    if self.gustLeft then
        self.gustLeft = self.gustLeft - dt
        self.gust = math.min(1, self.gust + dt * 1.2)
        if self.gustLeft <= 0 then self.gustLeft = nil end
    else
        self.gust = math.max(0, self.gust - dt * 0.6)
    end
    local target = self:blowing() and (0.5 + 0.5 * self.gust) or 0
    self.strength = self.strength + (target - self.strength) * math.min(1, dt * 1.5)

    local speed = 70 + 110 * self.strength
    if self.strength > 0.05 and cam.x then
        local x, y, w, h = view(40)
        if math.random() < dt * 7 * self.strength then
            table.insert(self.wisps, { x = x + math.random() * w, y = y + math.random() * h, life = 0, span = 1.4 + math.random(),
                length = 26 + math.random() * 40, wave = math.random() * 6, speed = speed * (0.8 + math.random() * 0.4) })
        end
        if math.random() < dt * 14 * self.strength then
            table.insert(self.leaves, { x = x + math.random() * w * 0.5, y = y + math.random() * h, life = 0, span = 2 + math.random() * 2,
                spin = math.random() * 6, spinSpeed = 4 + math.random() * 8, bob = math.random() * 6,
                color = LEAF_COLORS[math.random(#LEAF_COLORS)], speed = speed * (0.6 + math.random() * 0.6) })
        end
    end
    for i = #self.wisps, 1, -1 do
        local w = self.wisps[i]
        w.life = w.life + dt
        w.x = w.x + w.speed * dt
        if w.life >= w.span then table.remove(self.wisps, i) end
    end
    for i = #self.leaves, 1, -1 do
        local l = self.leaves[i]
        l.life = l.life + dt
        l.x = l.x + l.speed * dt
        l.y = l.y + math.sin(l.life * 3 + l.bob) * 12 * dt
        l.spin = l.spin + l.spinSpeed * dt
        if l.life >= l.span then table.remove(self.leaves, i) end
    end
end

-- leaves tumbling and wisps of air, in the world (camera attached)
function wind:draw()
    if self.strength <= 0.02 and #self.wisps == 0 and #self.leaves == 0 then return end
    pixelfx.world(function()
        for _, l in ipairs(self.leaves) do
            local fade = math.min(1, l.life / 0.3, (l.span - l.life) / 0.4)
            love.graphics.setColor(l.color[1], l.color[2], l.color[3], fade)
            local wide = math.abs(math.cos(l.spin)) * 2 + 0.5
            love.graphics.rectangle("fill", l.x - wide / 2, l.y - 0.5, wide, 1)
        end
        love.graphics.setLineWidth(1)
        for _, w in ipairs(self.wisps) do
            local fade = math.min(1, w.life / 0.4, (w.span - w.life) / 0.5) * 0.4
            local steps = 10
            for k = 1, steps do
                local f0, f1 = (k - 1) / steps, k / steps
                local x0, x1 = w.x - w.length * (1 - f0), w.x - w.length * (1 - f1)
                local y0 = w.y + math.sin(x0 * 0.12 + w.wave) * 2.5
                local y1 = w.y + math.sin(x1 * 0.12 + w.wave) * 2.5
                love.graphics.setColor(1, 1, 1, fade * math.sin(f1 * math.pi))
                love.graphics.line(x0, y0, x1, y1)
            end
        end
    end)
end

function wind:clear()
    self.wisps, self.leaves = {}, {}
end
