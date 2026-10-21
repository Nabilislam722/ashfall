-- World-space popups ("NOM!", "+8"), screen toasts and the current objective.
-- Popups live in world coordinates but are drawn after the camera so the
-- text stays crisp regardless of zoom.

floatTexts = {}

function floatTexts:spawn(x, y, text, color, options)
    options = options or {}
    table.insert(self, {
        x = x,
        y = y,
        text = text,
        color = color or {1, 1, 1},
        timer = 0,
        life = options.life or 1,
        rise = options.rise or 14,
        big = options.big or false,
    })
end

function floatTexts:update(dt)
    for i = #self, 1, -1 do
        local f = self[i]
        f.timer = f.timer + dt
        if f.timer >= f.life then
            table.remove(self, i)
        end
    end
end

function floatTexts:clear()
    for i = #self, 1, -1 do
        table.remove(self, i)
    end
end

function floatTexts:draw()
    for _, f in ipairs(self) do
        local progress = f.timer / f.life
        local sx, sy = cam:cameraCoords(f.x, f.y - f.rise * math.sin(progress * math.pi / 2))
        local alpha = progress < 0.7 and 1 or (1 - (progress - 0.7) / 0.3)
        local font = f.big and fonts.hud or fonts.float
        love.graphics.setFont(font)
        local tw = font:getWidth(f.text)
        love.graphics.setColor(0, 0, 0, alpha * 0.8)
        love.graphics.print(f.text, sx - tw / 2 + scale * 0.4, sy + scale * 0.4)
        love.graphics.setColor(f.color[1], f.color[2], f.color[3], alpha)
        love.graphics.print(f.text, sx - tw / 2, sy)
    end
    setWhite()
end

toast = { text = nil, timer = 0, life = 0 }

function showToast(text, duration)
    toast.text = text
    toast.life = duration or 3
    toast.timer = toast.life
end

objective = nil -- short text shown under the HUD while a quest is active

function updateToast(dt)
    if toast.timer > 0 then
        toast.timer = toast.timer - dt
        if toast.timer <= 0 then toast.text = nil end
    end
end

function drawToastAndObjective()
    local w = love.graphics.getWidth()

    if toast.text and not shop.active and not dialogue.active and not hemiExchange.active then
        local alpha = math.min(1, toast.timer / 0.4, (toast.life - toast.timer) / 0.25)
        love.graphics.setFont(fonts.toast)
        local tw = fonts.toast:getWidth(toast.text) + 10 * scale
        local th = fonts.toast:getHeight() + 2 * scale
        local tx = (w - tw) / 2
        local ty = love.graphics.getHeight() - th - 16 * scale
        love.graphics.setColor(0.05, 0.04, 0.06, 0.85 * alpha)
        love.graphics.rectangle("fill", tx, ty, tw, th, scale, scale)
        love.graphics.setColor(0.93, 0.84, 0.62, alpha)
        love.graphics.setLineWidth(math.max(2, math.floor(scale * 0.6)))
        love.graphics.rectangle("line", tx, ty, tw, th, scale, scale)
        love.graphics.setColor(1, 0.95, 0.8, alpha)
        love.graphics.printf(toast.text, tx, ty + scale, tw, "center")
        love.graphics.setLineWidth(1)
    end

    if objective then
        local font = fonts.hudGoal
        local hs = hudScale()
        love.graphics.setFont(font)
        local text = "Goal: " .. objective
        local ox, oy = 6, hudBottomY() + 2 * hs
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", ox, oy, font:getWidth(text) + 4 * hs, font:getHeight() + hs, hs * 0.5, hs * 0.5)
        love.graphics.setColor(1, 0.9, 0.55, 1)
        love.graphics.print(text, ox + 2 * hs, oy + hs * 0.4)
    end

    setWhite()
end
