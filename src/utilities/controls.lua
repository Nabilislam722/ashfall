-- The keys the game's actions are on, which the player can change in Settings
-- (src/ui/settingsMenu.lua). Each action has two keys (the second may be
-- empty); the mouse (aiming, and the left and right click items) stays as it
-- is. Saved with the other settings (src/utilities/settings.lua).
--
-- Gameplay asks controls:is(action, key) for a key pressed and
-- controls:down(action) for a key held; text that names a key asks
-- controls:label(action), or controls:fill("Press {book}").

controls = {}
controls.SLOTS = 2

controls.ACTIONS = {
    { id = "up", name = "Move up", keys = { "w", "up" } },
    { id = "down", name = "Move down", keys = { "s", "down" } },
    { id = "left", name = "Move left", keys = { "a", "left" } },
    { id = "right", name = "Move right", keys = { "d", "right" } },
    { id = "shadowStep", name = "Shadow Step", keys = { "space", "q" } },
    { id = "roll", name = "Roll", keys = { "lshift", "rshift" } },
    { id = "interact", name = "Talk, trade, save", keys = { "e", "return" } },
    { id = "fireball", name = "Fireball (hold to charge)", keys = { "e" } },
    { id = "items", name = "Item menu", keys = { "tab", "return" } },
    { id = "book", name = "Adventure Book", keys = { "b" } },
    { id = "journal", name = "Journal", keys = { "j" } },
    { id = "minimap", name = "Minimap", keys = { "n" } },
    { id = "zoomIn", name = "Zoom in", keys = { "=", "+" } },
    { id = "zoomOut", name = "Zoom out", keys = { "-" } },
    { id = "zoomReset", name = "Reset zoom", keys = { "0" } },
}
controls.byId = {}
for _, a in ipairs(controls.ACTIONS) do controls.byId[a.id] = a end

-- kept by the game: Esc (settings, back), F3 (developer), F11 (fullscreen), and
-- Backspace / Delete (they clear a key while one is being chosen)
controls.RESERVED = { escape = true, f3 = true, f11 = true, backspace = true, delete = true }

-- actions that may share a key, as what it does depends on where you are: E
-- talks to anyone close by, else casts the fireball; Enter talks, else opens
-- the item menu
local SHARE = { interact = { fireball = true, items = true }, fireball = { interact = true }, items = { interact = true } }

function controls:reset()
    self.keys = {}
    for _, a in ipairs(self.ACTIONS) do
        self.keys[a.id] = { a.keys[1], a.keys[2] }
    end
end
controls:reset()

-- a key LÖVE knows (a settings file can say anything)
local function known(key)
    return type(key) == "string" and #key > 0 and #key <= 20 and (pcall(love.keyboard.isDown, key))
end

function controls:canBind(key)
    return not self.RESERVED[key] and known(key)
end

function controls:key(id, slot)
    return self.keys[id] and self.keys[id][slot]
end

-- this key does this action
function controls:is(id, key)
    local keys = self.keys[id]
    if not keys then return false end
    for s = 1, self.SLOTS do
        if keys[s] == key then return true end
    end
    return false
end

-- this action's key is held
function controls:down(id)
    local keys = self.keys[id]
    if not keys then return false end
    for s = 1, self.SLOTS do
        if keys[s] and love.keyboard.isDown(keys[s]) then return true end
    end
    return false
end

local NAMES = {
    space = "Space", lshift = "Shift", rshift = "Right Shift", lctrl = "Ctrl", rctrl = "Right Ctrl",
    lalt = "Alt", ralt = "Right Alt", lgui = "Win", rgui = "Right Win", ["return"] = "Enter", tab = "Tab",
    up = "Up", down = "Down", left = "Left", right = "Right", capslock = "Caps Lock", pageup = "Page Up",
    pagedown = "Page Down", home = "Home", ["end"] = "End", insert = "Insert", numlock = "Num Lock",
    scrolllock = "Scroll Lock", pause = "Pause", menu = "Menu", kpenter = "Num Enter",
}

-- a key as the game prints it: "E", "Space", "Shift", "Num 5"
function controls.keyName(key)
    if NAMES[key] then return NAMES[key] end
    if key:sub(1, 2) == "kp" and #key > 2 then return "Num " .. key:sub(3):upper() end
    return key:upper()
end

-- an action's key as the game prints it ("-" if it has none)
function controls:label(id)
    local keys = self.keys[id] or {}
    local key = keys[1] or keys[2]
    return key and controls.keyName(key) or "-"
end

-- the four move keys in one word: "WASD", "Arrows", or each in turn
function controls:moveLabel()
    local four = { self:label("up"), self:label("left"), self:label("down"), self:label("right") }
    if four[1] == "Up" and four[2] == "Left" and four[3] == "Down" and four[4] == "Right" then return "Arrows" end
    for _, l in ipairs(four) do
        if #l ~= 1 then return table.concat(four, "/") end
    end
    return table.concat(four)
end

-- text with {action} (and {move}) put in as the keys are now: "Press {book} to open it"
function controls:fill(text)
    return (text:gsub("{(%w+)}", function(id)
        if id == "move" then return self:moveLabel() end
        if self.byId[id] then return self:label(id) end
    end))
end

-- puts a key on an action's slot. It comes off any other action (but those
-- that may share it); returns the names of the actions it was taken from.
function controls:bind(id, slot, key)
    local taken = {}
    for _, a in ipairs(self.ACTIONS) do
        if a.id ~= id and not (SHARE[id] and SHARE[id][a.id]) then
            local keys = self.keys[a.id]
            for s = 1, self.SLOTS do
                if keys[s] == key then
                    keys[s] = nil
                    table.insert(taken, a.name)
                end
            end
        end
    end
    local keys = self.keys[id]
    for s = 1, self.SLOTS do
        if keys[s] == key then keys[s] = nil end -- (not twice on one action)
    end
    keys[slot] = key
    return taken
end

function controls:clear(id, slot)
    self.keys[id][slot] = nil
end

-- for settings.json: { action = { key, key or "" } }
function controls:export()
    local out = {}
    for _, a in ipairs(self.ACTIONS) do
        local keys = self.keys[a.id]
        out[a.id] = { keys[1] or "", keys[2] or "" }
    end
    return out
end

-- from settings.json, checked: unknown actions and keys are left out, and an
-- action missing from the file keeps its default keys
function controls:import(saved)
    self:reset()
    if type(saved) ~= "table" then return end
    for _, a in ipairs(self.ACTIONS) do
        local keys = saved[a.id]
        if type(keys) == "table" then
            local list = {}
            for s = 1, self.SLOTS do
                local key = keys[s]
                if key ~= "" and self:canBind(key) then list[s] = key end
            end
            self.keys[a.id] = list
        end
    end
end
