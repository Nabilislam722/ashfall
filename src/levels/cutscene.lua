-- Scripted sequences written as plain functions that can pause themselves.
--
-- cutscene:play(function(cs)
--     cs:focus(448, 312)          -- glide the camera somewhere
--     cs:wait(1)
--     cs:say({ {speaker = "Rick", text = "NOM"} })
--     cs:walk(someNpc, 400, 200)  -- waits until the villager arrives
--     cs:focusPlayer()
-- end)
--
-- While a cutscene runs the player can't move or attack, but the rest of the
-- world keeps updating so villagers and Rick can act it out.

cutscene = {}
cutscene.active = false
cutscene.co = nil
cutscene.waitTimer = 0
cutscene.waitFn = nil
cutscene.onFinish = nil

function cutscene:play(fn, onFinish)
    self.active = true
    self.waitTimer = 0
    self.waitFn = nil
    self.onFinish = onFinish
    self.co = coroutine.create(function() fn(self) end)
    self:resume()
end

function cutscene:resume()
    local ok, err = coroutine.resume(self.co)
    if not ok then
        self.active = false
        error("cutscene error: " .. tostring(err))
    end
    if coroutine.status(self.co) == "dead" then
        self:finish()
    end
end

function cutscene:finish()
    self.active = false
    self.co = nil
    self.waitFn = nil
    cam.focus = nil
    local callback = self.onFinish
    self.onFinish = nil
    if callback then callback() end
end

function cutscene:update(dt)
    if not self.active then return end

    if self.waitTimer > 0 then
        self.waitTimer = self.waitTimer - dt
        if self.waitTimer > 0 then return end
    end

    if self.waitFn then
        if not self.waitFn(dt) then return end
        self.waitFn = nil
    end

    self:resume()
end

-- The helpers below are called from inside a running cutscene.

function cutscene:wait(seconds)
    self.waitTimer = seconds
    coroutine.yield()
end

function cutscene:waitUntil(fn)
    self.waitFn = fn
    coroutine.yield()
end

function cutscene:say(lines)
    dialogue:start(lines)
    self:waitUntil(function() return not dialogue.active end)
end

function cutscene:focus(x, y)
    cam.focus = { x = x, y = y }
end

-- keeps the camera on something that moves (anything with x and y fields)
function cutscene:follow(target, offsetY)
    cam.focus = { target = target, offsetY = offsetY }
end

function cutscene:focusPlayer()
    cam.focus = nil
end

function cutscene:walk(npc, x, y, speed)
    npc:walkTo(x, y, speed)
    self:waitUntil(function() return not npc.walking end)
end

-- the "VS" banner before a boss fight (src/ui/vsBanner.lua)
function cutscene:versus(left, right)
    vsBanner:play(left, right)
    self:waitUntil(function() return not vsBanner.active end)
end
