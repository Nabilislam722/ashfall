-- The Settings button in the top-right corner during play: a click opens
-- Settings (src/ui/settingsMenu.lua), as Esc does. A green dot on it says a
-- wallet is connected.

settingsButton = {}

local function rect()
    local hs = hudScale()
    local f = fonts.menuSmall
    local h = 13 * hs
    local w = h + f:getWidth("Settings") + 3 * hs
    return love.graphics.getWidth() - w - 6, 6, w, h
end

local function inside(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

-- a gear: a hub with eight teeth round it
local function gear(cx, cy, r)
    for i = 0, 7 do
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.rotate(i * math.pi / 4)
        love.graphics.rectangle("fill", -r * 0.22, -r, r * 0.44, r * 0.5)
        love.graphics.pop()
    end
    love.graphics.circle("fill", cx, cy, r * 0.72)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.circle("fill", cx, cy, r * 0.3)
end

-- it can be used (not hidden behind a window or a cutscene)
function settingsButton:visible()
    return gamestate == 1 and not pause.active and not dialogue.active and not shop.active
        and not hemiExchange.active and not manaWell.active and not cutscene.active and not respawn.pending
        and not book.active and not settingsMenu.active
end

-- returns true when the click was for it (so it doesn't swing the sword)
function settingsButton:mousepressed(x, y, button)
    if not self:visible() or not inside(x, y, rect()) then return false end
    if button == 1 then settingsMenu:open("game") end
    return true
end

function settingsButton:draw()
    if not self:visible() then return end
    local hs = hudScale()
    local bx, by, bw, bh = rect()
    local mx, my = love.mouse.getPosition()
    local hover = inside(mx, my, bx, by, bw, bh)

    love.graphics.setColor(0, 0, 0, hover and 0.75 or 0.5)
    love.graphics.rectangle("fill", bx, by, bw, bh, hs * 1.5, hs * 1.5)
    if hover then
        love.graphics.setLineWidth(math.max(2, math.floor(hs * 0.5)))
        love.graphics.setColor(1, 0.42, 0.1, 1)
        love.graphics.rectangle("line", bx, by, bw, bh, hs * 1.5, hs * 1.5)
    end
    love.graphics.setColor(1, 0.95, 0.88, 1)
    gear(bx + bh / 2, by + bh / 2, bh * 0.3)
    local f = fonts.menuSmall
    love.graphics.setFont(f)
    love.graphics.setColor(1, 0.95, 0.88, 1)
    love.graphics.print("Settings", bx + bh, by + (bh - f:getHeight()) / 2)
    if onchain:connected() then
        love.graphics.setColor(0.1, 0.1, 0.1, 1)
        love.graphics.circle("fill", bx + bw - hs * 1.6, by + hs * 1.6, hs * 1.6)
        love.graphics.setColor(0.35, 0.95, 0.45, 1)
        love.graphics.circle("fill", bx + bw - hs * 1.6, by + hs * 1.6, hs * 1.1)
    end
    love.graphics.setLineWidth(1)
    setWhite()
end
