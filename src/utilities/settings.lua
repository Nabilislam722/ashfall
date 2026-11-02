-- The player's settings: the graphics (fullscreen and VSync on desktop, camera
-- zoom, how dark nights and dungeons get, screen shake, particles, wind, a frame
-- counter), the sound, the minimap, and their keys
-- (src/utilities/controls.lua). Kept in
-- settings.json on this device (in the browser, in the browser's storage), apart
-- from the journey's save, so a new game keeps them.

local json = require("src/utilities/json")
local webBridge = require("src/utilities/webBridge")

settings = {}
settings.FILE = "settings.json"
settings.DEFAULTS = { master = 1, music = 1, effects = 1, minimap = true, fullscreen = true,
    vsync = true, zoom = 1, darkness = 1, shake = 1, particles = 1, wind = true, fps = false }
-- the settings chosen from a few: { value, as it's shown }
settings.CHOICES = {
    zoom = { { 0.8, "80%" }, { 0.9, "90%" }, { 1, "100%" }, { 1.1, "110%" }, { 1.25, "125%" }, { 1.5, "150%" } },
    darkness = { { 1, "Full" }, { 0.75, "Softer" }, { 0.5, "Softest" } }, -- (lighting.lua: how dark it gets)
    shake = { { 1, "Full" }, { 0.5, "Half" }, { 0, "Off" } },
    particles = { { 1, "Full" }, { 0.5, "Fewer" }, { 0, "Off" } },       -- (particle.lua: how many are made)
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
settings.values = copy(settings.DEFAULTS)

-- a volume from the file: 0 to 1, in tenths
local function level(v, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.floor(math.max(0, math.min(1, v)) * 10 + 0.5) / 10
end

function settings:load()
    local saved = nil
    if love.filesystem.getInfo(self.FILE) then
        local ok, text = pcall(love.filesystem.read, self.FILE)
        if ok and type(text) == "string" then
            local decoded = json.decode(text)
            if type(decoded) == "table" then saved = decoded end
        end
    end
    saved = saved or {}
    local d, v = self.DEFAULTS, {}
    v.master = level(saved.master, d.master)
    v.music = level(saved.music, d.music)
    v.effects = level(saved.effects, d.effects)
    for key, list in pairs(self.CHOICES) do
        v[key] = d[key]
        for _, c in ipairs(list) do
            if tonumber(saved[key]) == c[1] then v[key] = c[1] end
        end
    end
    v.minimap = saved.minimap ~= false
    v.fullscreen = saved.fullscreen ~= false
    v.vsync = saved.vsync ~= false
    v.wind = saved.wind ~= false
    v.fps = saved.fps == true
    self.values = v
    controls:import(saved.keys)
    self:apply()
    zoomLevel, zoomTarget = v.zoom, v.zoom -- (the camera starts there)
    -- desktop: the window as it was left
    if love.system.getOS() ~= "Web" and v.fullscreen ~= (fullscreen == true) then toggleFullscreen() end
end

function settings:save()
    local out = copy(self.values)
    out.keys = controls:export()
    pcall(love.filesystem.write, self.FILE, json.encode(out))
end

-- the settings at work
function settings:apply()
    local v = self.values
    love.audio.setVolume(v.master)
    dj.volume("effect", v.effects)
    shake.scale = v.shake
    if minimap then minimap.visible = v.minimap end
    -- VSync: desktop (in the browser the page draws as often as the browser lets it)
    if love.system.getOS() ~= "Web" and love.window and love.window.getVSync then
        local want = v.vsync and 1 or 0
        if love.window.getVSync() ~= want then love.window.setVSync(want) end
    end
end

function settings:set(key, value)
    self.values[key] = value
    self:apply()
    if key == "zoom" then setZoomLevel(value) end -- (only then: the wheel's zoom is the player's own)
    self:save()
end

-- the minimap shown or not (N), remembered
function settings:toggleMinimap()
    self:set("minimap", not minimap.visible)
end

-- the window went fullscreen or back (desktop), remembered
function settings:fullscreenChanged()
    if love.system.getOS() == "Web" then return end
    self.values.fullscreen = fullscreen == true
    self:save()
end

-- a chosen setting as it's shown ("Full", "125%")
function settings:choiceName(key)
    for _, c in ipairs(self.CHOICES[key]) do
        if c[1] == self.values[key] then return c[2] end
    end
    return self.CHOICES[key][1][2]
end

-- the next (1) or the one before (-1), round and round
function settings:cycle(key, dir)
    local list, at = self.CHOICES[key], 1
    for i, c in ipairs(list) do
        if c[1] == self.values[key] then at = i end
    end
    self:set(key, list[(at - 1 + dir) % #list + 1][1])
end

-- "on" or "off", or nil where there's no fullscreen to be had (an iPhone). In
-- the browser the page is asked now and then (pollFullscreen), as Esc can leave
-- fullscreen without the game hearing it.
function settings:fullscreenState()
    if webBridge.isAvailable() then return self.webFullscreen end
    return fullscreen and "on" or "off"
end

function settings:pollFullscreen(dt)
    self.fullscreenPoll = (self.fullscreenPoll or 0) - dt
    if self.fullscreenPoll > 0 then return end
    self.fullscreenPoll = 0.5
    if webBridge.isAvailable() then self.webFullscreen = webBridge.fullscreen() end
end

-- (after a toggle the page takes a moment to say)
function settings:askFullscreenSoon()
    self.fullscreenPoll = 0.15
end
