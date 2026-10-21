-- Monster spawners: glowing summoning circles placed in a map's "Spawners"
-- object layer (object name = monster type: skeleton, bat or eye).
--
-- Like a dungeon in an anime, the floor keeps producing monsters: while the
-- player is nearby, each circle summons a monster whenever it has fewer than
-- `max` alive (properties: max, interval in seconds, form). The runes spin up,
-- a pillar of light rises and the monster steps out. It prowls around its
-- circle until the hero comes within its aggro range (property: aggro, in
-- pixels), then gives chase. Spawned monsters don't count as defeated for
-- good, so the dungeon is a hunting ground for ears.

spawners = {}

local SUMMON_TIME = 1.1
local ACTIVE_RANGE = 230   -- the player is close enough to wake a circle
local SAFE_RANGE = 34      -- never summon right on top of the player
local AGGRO_RANGE = 96     -- how close the hero can get before a monster gives chase
local SOUND = "sounds/items/manaFull.wav"

local COLORS = {
    skeleton = { 1, 0.36, 0.3 },
    bat = { 0.72, 0.42, 1 },
    eye = { 0.32, 0.9, 1 },
}
-- spawnEnemy takes the top-left corner of each monster's body
local BODY = { skeleton = { 6, 8 }, bat = { 5.5, 4.5 }, eye = { 6, 8 } }

function loadSpawners(map, mapName)
    for i = #spawners, 1, -1 do table.remove(spawners, i) end
    local layer = map.layers["Spawners"]
    if not layer then return end
    for _, obj in ipairs(layer.objects) do
        local kind = obj.name
        if BODY[kind] then
            local props = obj.properties or {}
            table.insert(spawners, {
                x = obj.x + (obj.width or 16) / 2,
                y = obj.y + (obj.height or 16) / 2,
                kind = kind,
                form = tonumber(props.form) or 1,
                max = tonumber(props.max) or 2,
                interval = tonumber(props.interval) or 6,
                aggro = tonumber(props.aggro) or AGGRO_RANGE,
                alive = 0,
                timer = 0.4 + math.random() * 1.2, -- the room fills up as you walk in
                angle = math.random() * math.pi * 2,
                summon = nil,
                flash = 0,
                motes = {},
            })
        end
    end
end

function spawners:summon(sp)
    local body = BODY[sp.kind]
    local enemy = spawnEnemy(sp.x - body[1], sp.y - body[2], sp.kind, { form = sp.form })
    if enemy then
        enemy.spawner = sp
        enemy.aggroRange = sp.aggro -- prowls around its circle until the hero comes close
        sp.alive = sp.alive + 1
    end
    sp.flash = 1
    shake:start(0.08, 1, 0.02)
end

function spawners:update(dt)
    local px, py = player:getX(), player:getY()
    for _, sp in ipairs(spawners) do
        sp.angle = sp.angle + dt * (sp.summon and 4 or 0.5)
        sp.flash = math.max(0, sp.flash - dt * 3)

        if sp.summon then
            sp.summon = sp.summon + dt
            if math.random() < dt * 30 then
                local a = math.random() * math.pi * 2
                local r = 6 + math.random() * 8
                table.insert(sp.motes, { x = sp.x + math.cos(a) * r, y = sp.y + math.sin(a) * r * 0.5, life = 0.6 })
            end
            if sp.summon >= SUMMON_TIME then
                sp.summon = nil
                sp.timer = sp.interval
                self:summon(sp)
            end
        else
            local d = distanceBetween(sp.x, sp.y, px, py)
            if sp.alive < sp.max and d < ACTIVE_RANGE and d > SAFE_RANGE and not isPlayerFrozen() then
                sp.timer = sp.timer - dt
                if sp.timer <= 0 then
                    sp.summon = 0
                    dj.play(SOUND, "static", "effect", 0.35, 0.55 + math.random() * 0.15)
                end
            end
        end

        for i = #sp.motes, 1, -1 do
            local m = sp.motes[i]
            m.y = m.y - 26 * dt
            m.life = m.life - dt
            if m.life <= 0 then table.remove(sp.motes, i) end
        end
    end
end

-- the circle on the floor (drawn under everything that stands on the ground)
function spawners:drawGround()
    pixelfx.world(function()
        local t = love.timer.getTime()
        for _, sp in ipairs(spawners) do
            local c = COLORS[sp.kind]
            local power = sp.summon and math.min(1, sp.summon / SUMMON_TIME) or 0
            local pulse = 0.5 + 0.5 * math.sin(t * 2 + sp.x)
            local alpha = 0.28 + 0.12 * pulse + 0.6 * power
            local r = 12 + 2 * power

            love.graphics.push()
            love.graphics.translate(sp.x, sp.y)
            love.graphics.scale(1, 0.55) -- lying flat on the floor
            love.graphics.setBlendMode("add")
            love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.3 * power)
            love.graphics.circle("fill", 0, 0, r + 2)
            love.graphics.setLineWidth(1.8)
            love.graphics.setColor(c[1], c[2], c[3], alpha)
            love.graphics.circle("line", 0, 0, r)
            love.graphics.circle("line", 0, 0, r * 0.68)
            -- runes around the ring, and a star inside
            for i = 0, 7 do
                local a = sp.angle + i * math.pi / 4
                love.graphics.rectangle("fill", math.cos(a) * r * 0.84 - 1, math.sin(a) * r * 0.84 - 1, 2, 2)
            end
            local star = {}
            for i = 0, 4 do
                local a = -sp.angle * 0.7 + i * math.pi * 4 / 5
                table.insert(star, math.cos(a) * r * 0.62)
                table.insert(star, math.sin(a) * r * 0.62)
            end
            love.graphics.polygon("line", star)
            love.graphics.setBlendMode("alpha")
            love.graphics.pop()
        end
    end)
    setWhite()
end

-- the pillar of light while summoning, rising motes, and the flash
function spawners:drawAir()
    pixelfx.world(function()
        for _, sp in ipairs(spawners) do
            local c = COLORS[sp.kind]
            love.graphics.setBlendMode("add")
            if sp.summon then
                local power = math.min(1, sp.summon / SUMMON_TIME)
                local width = 5 + 7 * power
                for i = 0, 5 do
                    local a = (0.1 + 0.25 * power) * (1 - i / 6)
                    love.graphics.setColor(c[1], c[2], c[3], a)
                    love.graphics.rectangle("fill", sp.x - width / 2, sp.y - 34 + i * 6, width, 6)
                end
            end
            for _, m in ipairs(sp.motes) do
                love.graphics.setColor(c[1], c[2], c[3], math.min(1, m.life * 2))
                love.graphics.rectangle("fill", m.x - 0.75, m.y - 0.75, 1.5, 1.5)
            end
            if sp.flash > 0 then
                love.graphics.setColor(1, 1, 1, sp.flash * 0.8)
                love.graphics.circle("fill", sp.x, sp.y - 4, 10 * (1.4 - sp.flash * 0.4))
            end
            love.graphics.setBlendMode("alpha")
        end
    end)
    setWhite()
end
