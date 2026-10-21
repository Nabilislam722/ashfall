-- Dungeon lighting. A map with an "ambient" property (0 to 1) is darkened by
-- that much; light sources cut through the dark: the player, objects in the
-- map's "Lights" layer (properties: radius, color "r,g,b", flicker), spawner
-- circles, checkpoint crystals, the Storm Staff's lightning and Gula's spells.
-- Coloured lights also glow additively.

lighting = {}
lighting.ambient = 0
lighting.lights = {}

local glowImage = nil

-- a soft round light, smoothly filtered (the game's pixel-art "nearest" filter
-- would show it as stepped rings once it is stretched over the screen)
local function glow()
    if not glowImage then
        local size = 256
        local imageData = love.image.newImageData(size, size)
        imageData:mapPixel(function(x, y)
            local d = math.sqrt((x - size / 2 + 0.5) ^ 2 + (y - size / 2 + 0.5) ^ 2) / (size / 2)
            local a = math.max(0, 1 - d)
            return 1, 1, 1, a * a * (3 - 2 * a)
        end)
        glowImage = love.graphics.newImage(imageData)
        glowImage:setFilter("linear", "linear")
    end
    return glowImage
end

local function parseColor(text)
    local r, g, b = tostring(text or ""):match("([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
    if not r then return { 1, 0.72, 0.4 } end
    return { tonumber(r), tonumber(g), tonumber(b) }
end

function loadLighting(map)
    lighting.ambient = tonumber(map.properties and map.properties.ambient) or 0
    lighting.lights = {}
    local layer = map.layers["Lights"]
    if not layer then return end
    for _, obj in ipairs(layer.objects) do
        local props = obj.properties or {}
        table.insert(lighting.lights, {
            x = obj.x + (obj.width or 0) / 2,
            y = obj.y + (obj.height or 0) / 2,
            radius = tonumber(props.radius) or 48,
            color = parseColor(props.color),
            flicker = props.flicker ~= false,
            seed = math.random() * 100,
        })
    end
end

-- how dark it is right now: the map's own darkness, or night outdoors
function lighting:level()
    return math.max(self.ambient, worldClock:darkness())
end

function lighting:active()
    return gamestate == 1 and self:level() > 0
end

-- every light this frame: { x, y (world), radius, color, strength }
function lighting:sources()
    local t = love.timer.getTime()
    local list = {}
    for _, l in ipairs(self.lights) do
        local f = l.flicker and (0.92 + 0.05 * math.sin(t * 9 + l.seed) + 0.03 * math.sin(t * 23 + l.seed * 2)) or 1
        table.insert(list, { x = l.x, y = l.y, radius = l.radius * f, color = l.color, strength = 1 })
    end
    table.insert(list, { x = player:getX(), y = player:getY() - 4, radius = worldClock:outdoors() and 56 or 74, strength = 0.95 })
    staff:lights(list) -- the Storm Staff's lightning
    fireballs:lights(list) -- fireballs, and the one being charged
    for _, sp in ipairs(spawners) do
        local strength = sp.summon and 1 or 0.55
        table.insert(list, { x = sp.x, y = sp.y, radius = sp.summon and 46 or 30, strength = strength })
    end
    for _, cp in ipairs(checkpoints) do
        table.insert(list, { x = cp.x, y = cp.y - 18, radius = 40, color = { 1, 0.55, 0.2 }, strength = 0.8 })
    end
    if lairStory and lairStory.rick then
        -- his lightning lights the room up for an instant with every strike
        local rick = lairStory.rick
        local strike = rick.aura and rick.aura:flashing() or 0
        local surge = rick.aura and rick.aura.surging or 0
        table.insert(list, { x = rick.x, y = rick.y - 12, radius = 62 + 70 * strike + 24 * surge, color = { 0.55, 0.82, 1 }, strength = 1 })
    end
    if lairStory and lairStory.gula then
        local g = lairStory.gula
        local color = g.frozen and { 0.6, 0.85, 1 } or g.berserk and { 1, 0.2, 0.2 } or { 0.75, 0.3, 1 }
        table.insert(list, { x = g.x, y = g.y - 24, radius = g.berserk and 90 or 70, color = color, strength = 0.9 })
        g:addLights(list) -- its Hunger Nova
        if g.beam then
            local b = g.beam
            local power = g:beamPower()
            local r, gr, bl = g:beamColor()
            for i = 0, 5 do
                local f = i / 5
                table.insert(list, { x = b.x1 + (b.x2 - b.x1) * f, y = b.y1 + (b.y2 - b.y1) * f,
                    radius = 46 + 30 * power, color = { r, gr, bl }, strength = power })
            end
            -- the lightning flash: for an instant the whole hall is lit
            if b.t < 0.16 then
                table.insert(list, { x = (b.x1 + b.x2) / 2, y = (b.y1 + b.y2) / 2, radius = 340, strength = 1 - b.t / 0.16 })
            end
        elseif g.state == "laserWind" then
            local mx, my = g:mouth()
            local r, gr, bl = g:beamColor()
            table.insert(list, { x = mx, y = my, radius = 30 + math.random() * 14, color = { r, gr, bl }, strength = 0.9 })
        end
    end
    for _, loot in ipairs(loots) do
        if loot.rare then table.insert(list, { x = loot.x, y = loot.y, radius = 22, color = { 1, 0.85, 0.4 }, strength = 0.8 }) end
    end
    return list
end

-- additive coloured glow, drawn in the world with the camera attached
function lighting:drawGlow()
    if not self:active() then return end
    local image = glow()
    love.graphics.setBlendMode("add")
    for _, l in ipairs(self:sources()) do
        if l.color then
            local s = l.radius * 2 / image:getWidth()
            love.graphics.setColor(l.color[1], l.color[2], l.color[3], 0.22 * l.strength)
            love.graphics.draw(image, l.x, l.y, 0, s, s, image:getWidth() / 2, image:getHeight() / 2)
        end
    end
    love.graphics.setBlendMode("alpha")
    setWhite()
end

-- The darkness, with every light cut out of it (screen space). A shader works
-- out each pixel's light: the darkness level, brightened back towards full by
-- every light nearby, and that is multiplied over the scene. (Not a light-map
-- canvas: the web build's canvases have only 4 bits per channel, which showed as
-- stepped rings around every light.)
local MAX_LIGHTS = 32
local darknessShader = nil

local function shader()
    if not darknessShader then
        darknessShader = love.graphics.newShader([[
            extern vec4 lights[32];   // x, y (pixels), radius (pixels), strength
            extern vec3 colors[32];
            extern float count;
            extern vec3 base;         // the light where no lamp reaches
            vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
                vec3 light = base;
                for (int i = 0; i < 32; i++) {
                    if (float(i) >= count) break;
                    vec4 l = lights[i];
                    float a = clamp(1.0 - length(pixel - l.xy) / l.z, 0.0, 1.0);
                    light += colors[i] * (l.w * a * a * (3.0 - 2.0 * a));
                }
                return vec4(min(light, vec3(1.0)), 1.0);
            }
        ]])
    end
    return darknessShader
end

function lighting:drawDarkness()
    if not self:active() then return end
    local w, h = love.graphics.getDimensions()
    local dpi = love.graphics.getDPIScale()
    local zoom = getRenderScale()
    local level = self:level()
    -- a dungeon's gloom, or the sky's colour (golden at dusk, blue at night, rosy at dawn)
    local tint = self.ambient > 0 and { 0.92, 0.88, 1 } or { worldClock:skyTint() }

    -- the lights on screen (in pixels), each brightening up to `level`
    local lights, colors = {}, {}
    for _, l in ipairs(self:sources()) do
        local sx, sy = cam:cameraCoords(l.x, l.y)
        local r = l.radius * zoom
        if #lights < MAX_LIGHTS and sx + r > 0 and sx - r < w and sy + r > 0 and sy - r < h then
            local c = l.color or { 1, 1, 1 }
            table.insert(lights, { sx * dpi, sy * dpi, r * dpi, l.strength })
            table.insert(colors, { level * (0.6 + 0.4 * c[1]), level * (0.6 + 0.4 * c[2]), level * (0.6 + 0.4 * c[3]) })
        end
    end

    local s = shader()
    s:send("base", { (1 - level) * tint[1], (1 - level) * tint[2], (1 - level) * tint[3] })
    s:send("count", #lights)
    if #lights > 0 then
        s:send("lights", unpack(lights))
        s:send("colors", unpack(colors))
    end
    love.graphics.push("all")
    love.graphics.setShader(s)
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.pop()
end
