-- Wooden signposts placed in a map's "Signs" object layer.
-- The post is drawn in the world; its text pops up when the player is close.

signs = {}

local READ_RADIUS = 26

function loadSigns(map)
    for index = #signs, 1, -1 do
        table.remove(signs, index)
    end

    if not map.layers["Signs"] then return end

    for _, object in pairs(map.layers["Signs"].objects) do
        local text = object.properties and object.properties.text or object.name
        if text and text ~= "" then
            local sign = {
                x = object.x + (object.width or 16) / 2,
                y = object.y + (object.height or 16),
                text = text
            }
            spawnWall(sign.x - 3, sign.y - 4, 6, 4)
            table.insert(signs, sign)
        end
    end
end

local function drawPost(sign)
    local x, y = math.floor(sign.x), math.floor(sign.y)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse("fill", x, y, 4, 1.5)
    love.graphics.setColor(0.22, 0.12, 0.08, 1)
    love.graphics.rectangle("fill", x - 1, y - 9, 2, 9)
    love.graphics.rectangle("fill", x - 7, y - 16, 14, 9)
    love.graphics.setColor(0.62, 0.40, 0.20, 1)
    love.graphics.rectangle("fill", x - 6, y - 15, 12, 7)
    love.graphics.setColor(0.78, 0.55, 0.30, 1)
    love.graphics.rectangle("fill", x - 6, y - 15, 12, 1)
    love.graphics.setColor(0.35, 0.20, 0.10, 1)
    love.graphics.rectangle("fill", x - 4, y - 13, 8, 1)
    love.graphics.rectangle("fill", x - 4, y - 11, 6, 1)
    setWhite()
end

function signs:collect(items)
    for _, sign in ipairs(signs) do
        table.insert(items, { y = sign.y, draw = drawPost, arg = sign })
    end
end

function signs:drawOverlay()
    if isPlayerFrozen() or pause.active then return end
    for _, sign in ipairs(signs) do
        if distanceBetween(sign.x, sign.y - 4, player:getX(), player:getY()) < READ_RADIUS then
            local sx, sy = cam:cameraCoords(sign.x, sign.y - 20)
            love.graphics.setFont(fonts.small)
            local tw = fonts.small:getWidth(sign.text) + 6 * scale
            local th = fonts.small:getHeight() + 2 * scale
            love.graphics.setColor(0.18, 0.10, 0.05, 0.95)
            love.graphics.rectangle("fill", sx - tw / 2, sy - th, tw, th, scale * 0.6, scale * 0.6)
            love.graphics.setColor(0.78, 0.55, 0.30, 1)
            love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.5)))
            love.graphics.rectangle("line", sx - tw / 2, sy - th, tw, th, scale * 0.6, scale * 0.6)
            love.graphics.setColor(1, 0.92, 0.70, 1)
            love.graphics.printf(sign.text, sx - tw / 2, sy - th + scale, tw, "center")
            love.graphics.setLineWidth(1)
            setWhite()
        end
    end
end
