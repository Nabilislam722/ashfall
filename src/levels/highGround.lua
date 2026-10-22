-- High ground: up on a plateau (the map's "HighGround" rectangles) the camera
-- draws back so you see further from up there, and eases back in as you come
-- down. A rectangle of type "stairs" is a ramp, higher toward its top edge, so
-- the view opens up step by step as you climb.
--
-- It multiplies the player's own zoom (mouse wheel, + and -), which it leaves alone.

highGround = { rects = {}, amount = 0 }

local VIEW = 0.8   -- the zoom at the top: a quarter more to see each way
local EASE = 2.5   -- how quickly the view follows (per second)

-- how high a point stands: 0 on the ground, 1 on top
function highGround:at(x, y)
    for _, r in ipairs(self.rects) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            if r.stairs then
                return math.max(0, math.min(1, 1 - (y - r.y) / r.h))
            end
            return 1
        end
    end
    return 0
end

function loadHighGround(map)
    highGround.rects = {}
    local layer = map.layers["HighGround"]
    if layer then
        for _, o in ipairs(layer.objects) do
            table.insert(highGround.rects, { x = o.x, y = o.y, w = o.width, h = o.height, stairs = o.type == "stairs" })
        end
    end
    -- a new map starts at the right height, without a zoom on arrival
    highGround.amount = highGround:at(player:getX(), player:getY())
end

function highGround:update(dt)
    if gamestate ~= 1 or not gameMap then return end
    local target = self:at(player:getX(), player:getY())
    if math.abs(target - self.amount) < 0.002 then
        self.amount = target
    else
        self.amount = self.amount + (target - self.amount) * (1 - math.exp(-EASE * dt))
    end
end

-- the camera's zoom factor for the height the hero stands at
function highGround:zoom()
    return 1 + (VIEW - 1) * self.amount
end
