-- Everything on-chain goes through web/bridge.js (browser builds only): wallet,
-- Hemi Exchange, saves and staking. This keeps the page's latest state in
-- onchain.remote and runs the game's requests one at a time:
--
--   onchain:start("save", { data = text }, function(remote, ok) ... end)
--
-- The page only runs one action at a time (the ☰ menu shares it), so a request
-- made while something else is running waits in a queue. The callback runs once
-- the page has finished that request; ok is false when it failed or was
-- cancelled in the wallet, and remote.error says why.

local webBridge = require("src/utilities/webBridge")

onchain = {}
onchain.remote = {}
onchain.task = nil     -- { action, run, onDone } waiting for the page
onchain.queue = {}     -- requests waiting for the page to be free
onchain.pollTimer = 0

local ACTIVE_POLL = 0.25
local IDLE_POLL = 1.5   -- picks up wallet changes made in the page menu

function onchain:available()
    return webBridge.isAvailable()
end

function onchain:busy()
    return self.task ~= nil or self.remote.state == "working"
end

-- for player actions: looks at the page first, so a request that has just
-- finished doesn't make the next one wait
function onchain:busyNow()
    if self.task then self:poll() end
    return self:busy()
end

function onchain:connected()
    return (self.remote.address or "") ~= ""
end

-- on-chain saves can be written: a wallet is connected and the server knows the contract
function onchain:canSave()
    return self:available() and self:connected() and self.remote.saves == "1"
end

function onchain:poll()
    if not self:available() then return self.remote end
    self.remote = webBridge.poll()
    if hemiExchange then hemiExchange:onRemote(self.remote) end

    local task = self.task
    if task and self.remote.run == task.run and self.remote.state ~= "working" then
        self.task = nil
        if task.onDone then task.onDone(self.remote, self.remote.state ~= "error") end
    end
    return self.remote
end

-- returns "ok", "queued" or "unavailable"
function onchain:start(action, params, onDone)
    if not self:available() then
        if onDone then onDone({ state = "error", error = "This needs the browser version of the game." }, false) end
        return "unavailable"
    end
    if self.task then
        table.insert(self.queue, { action = action, params = params, onDone = onDone })
        return "queued"
    end
    local result = webBridge.start(action, params)
    if result == "ok" then
        self.remote = webBridge.poll()
        self.task = { action = action, run = self.remote.run, onDone = onDone }
        self.pollTimer = math.min(self.pollTimer, ACTIVE_POLL)
        if hemiExchange then hemiExchange:onRemote(self.remote) end
        return "ok"
    elseif result == "busy" then
        table.insert(self.queue, { action = action, params = params, onDone = onDone })
        return "queued"
    end
    if onDone then
        onDone({ state = "error", error = "The page couldn't start that (" .. tostring(result) .. ")." }, false)
    end
    return result
end

function onchain:update(dt)
    if not self:available() then return end
    local active = self.task or #self.queue > 0 or self.remote.state == "working" or gamestate == 0
        or (hemiExchange and hemiExchange.active) or (topMenu and topMenu.open) or (manaWell and manaWell.active)
    if active and self.pollTimer > ACTIVE_POLL then self.pollTimer = ACTIVE_POLL end
    self.pollTimer = self.pollTimer - dt
    if self.pollTimer > 0 then return end
    self.pollTimer = active and ACTIVE_POLL or IDLE_POLL
    self:poll()

    if not self.task and #self.queue > 0 and self.remote.state ~= "working" then
        local nextRequest = table.remove(self.queue, 1)
        self:start(nextRequest.action, nextRequest.params, nextRequest.onDone)
    end
end

function onchain:reset()
    self.task = nil
    self.queue = {}
end
