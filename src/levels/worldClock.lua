-- The world's clock. Days go by while you play: dawn, morning, afternoon,
-- evening and night, and the outdoors darkens after sunset (src/levels/lighting.lua).
-- A day lasts DAY_LENGTH seconds of play; resting at the inn skips to the next
-- morning.
--
-- data.day   which day it is, from 1
-- data.clock the time of day: 0 at dawn .. 1 at the next dawn

worldClock = {}

local DAY_LENGTH = 360 -- seconds of play per day
local NIGHT_DARKNESS = 0.62
local DUSK, NIGHT = 0.62, 0.74
local PHASES = { { 0, "Dawn" }, { 0.06, "Morning" }, { 0.36, "Afternoon" }, { DUSK, "Evening" }, { NIGHT, "Night" } }
local OUTDOORS = { village = true, test = true, test2 = true, woods = true }

worldClock.DAY_LENGTH = DAY_LENGTH

function worldClock:update(dt)
    if gamestate ~= 1 or pause.active or cutscene.active or curtain.state ~= 0 then return end
    data.clock = data.clock + dt / DAY_LENGTH
    if data.clock >= 1 then
        data.clock = data.clock - 1
        self:newDay()
    end
end

function worldClock:newDay()
    data.day = data.day + 1
    local news = villageStory:onNewDay()
    local text = "Day " .. data.day
    if data.day == 2 then text = text .. ":  the wind is picking up" end
    if news then text = text .. (data.day == 2 and ", and " or ":  ") .. news end
    showToast(text, 4)
end

-- rest until the next morning (at the inn)
function worldClock:sleep()
    data.clock = 0.1
    self:newDay()
end

function worldClock:phase()
    local name = PHASES[1][2]
    for _, p in ipairs(PHASES) do
        if data.clock >= p[1] then name = p[2] end
    end
    return name
end

function worldClock:outdoors()
    return OUTDOORS[loadedMap] == true
end

function worldClock:isNight()
    return data.clock >= NIGHT or data.clock < 0.03
end

-- how dark the outdoors is right now (0 by day)
function worldClock:darkness()
    if not self:outdoors() then return 0 end
    local c = data.clock
    if c < 0.06 then return NIGHT_DARKNESS * (1 - c / 0.06) end
    if c < DUSK then return 0 end
    if c < NIGHT then return NIGHT_DARKNESS * (c - DUSK) / (NIGHT - DUSK) end
    return NIGHT_DARKNESS
end

-- the colour of the outdoor light while it is dark (src/levels/lighting.lua):
-- golden as the sun sets, deep blue at night, rosy at dawn
local WHITE, GOLDEN, NIGHT_BLUE, ROSY = { 1, 1, 1 }, { 1, 0.86, 0.66 }, { 0.58, 0.68, 1 }, { 1, 0.84, 0.8 }

local function mix(a, b, f)
    return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
end

-- (it shifts gradually: day white -> gold -> night blue -> rosy -> white again)
function worldClock:skyTint()
    local c = data.clock
    if c < 0.06 then
        local f = c / 0.06
        if f < 0.5 then return mix(NIGHT_BLUE, ROSY, f / 0.5) end
        return mix(ROSY, WHITE, (f - 0.5) / 0.5)
    end
    if c < DUSK then return 1, 1, 1 end
    if c < NIGHT then
        local f = (c - DUSK) / (NIGHT - DUSK)
        if f < 0.5 then return mix(WHITE, GOLDEN, f / 0.5) end
        return mix(GOLDEN, NIGHT_BLUE, (f - 0.5) / 0.5)
    end
    return NIGHT_BLUE[1], NIGHT_BLUE[2], NIGHT_BLUE[3]
end
