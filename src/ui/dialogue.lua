-- Story dialogue box with a typewriter effect and a speaker portrait.
-- dialogue:start({ {speaker = "Elder Mara", portrait = image, portraitQuad = quad (optional), text = "..."}, ... }, onFinish)

dialogue = {}
dialogue.active = false
dialogue.lines = {}
dialogue.index = 1
dialogue.shown = 0
dialogue.speed = 55 -- characters per second
dialogue.blink = 0
dialogue.onFinish = nil

local NAME_COLORS = {
    ["Rick"] = {0.95, 0.55, 0.30},
    ["Elder Mara"] = {0.78, 0.62, 0.95},
}

function dialogue:start(lines, onFinish)
    self.lines = lines
    self.index = 1
    self.shown = 0
    self.blink = 0
    self.onFinish = onFinish
    self.active = true
end

function dialogue:current()
    return self.lines[self.index]
end

function dialogue:update(dt)
    if not self.active then return end
    self.blink = self.blink + dt

    local line = self:current()
    if self.shown < #line.text then
        local before = math.floor(self.shown)
        self.shown = math.min(#line.text, self.shown + self.speed * dt)
        local now = math.floor(self.shown)
        if now ~= before and now % 4 == 0 and line.text:sub(now, now) ~= " " then
            local pitch = line.speaker == "Rick" and 0.7 or 1.25
            dj.play(sounds.ui.click, "static", "effect", 0.35, pitch + math.random() * 0.1)
        end
    end
end

function dialogue:advance()
    if not self.active then return end
    local line = self:current()
    if self.shown < #line.text then
        self.shown = #line.text
        return
    end

    self.index = self.index + 1
    self.shown = 0
    self.blink = 0
    if self.index > #self.lines then
        self.active = false
        local callback = self.onFinish
        self.onFinish = nil
        if callback then callback() end
    end
end

function dialogue:keypressed(key)
    if key == "space" or key == "e" or key == "return" or key == "kpenter" or key == "z" or key == "x" then
        self:advance()
    end
end

function dialogue:draw()
    if not self.active then return end
    local line = self:current()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    local boxW = math.min(w * 0.76, 200 * scale)
    local boxH = 44 * scale
    local boxX = (w - boxW) / 2
    local boxY = h - boxH - 8 * scale
    local pad = 4 * scale
    local border = math.max(2, math.floor(scale * 0.8))

    -- frame
    love.graphics.setColor(0.05, 0.04, 0.06, 0.94)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, scale, scale)
    love.graphics.setLineWidth(border)
    love.graphics.setColor(0.93, 0.84, 0.62, 1)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, scale, scale)

    -- portrait
    local textX = boxX + pad
    if line.portrait then
        local size = boxH - pad * 2
        love.graphics.setColor(0.16, 0.13, 0.15, 1)
        love.graphics.rectangle("fill", boxX + pad, boxY + pad, size, size, scale * 0.5, scale * 0.5)
        love.graphics.setColor(0.93, 0.84, 0.62, 0.6)
        love.graphics.rectangle("line", boxX + pad, boxY + pad, size, size, scale * 0.5, scale * 0.5)

        local image = line.portrait
        local quad = line.portraitQuad
        local iw, ih = image:getDimensions()
        if quad then
            local _, _, qw, qh = quad:getViewport()
            iw, ih = qw, qh
        end
        local s = math.max(1, math.floor((size * 0.86) / math.max(iw, ih)))
        setWhite()
        if quad then
            love.graphics.draw(image, quad, boxX + pad + size / 2, boxY + pad + size / 2, 0, s, s, iw / 2, ih / 2)
        else
            love.graphics.draw(image, boxX + pad + size / 2, boxY + pad + size / 2, 0, s, s, iw / 2, ih / 2)
        end
        textX = boxX + pad * 2 + size
    end

    -- speaker name tab
    if line.speaker then
        love.graphics.setFont(fonts.dialogueName)
        local nameW = fonts.dialogueName:getWidth(line.speaker) + pad * 2
        local nameH = fonts.dialogueName:getHeight() + scale
        local nameX = textX
        local nameY = boxY - nameH + border
        love.graphics.setColor(0.05, 0.04, 0.06, 0.94)
        love.graphics.rectangle("fill", nameX, nameY, nameW, nameH, scale * 0.5, scale * 0.5)
        love.graphics.setColor(0.93, 0.84, 0.62, 1)
        love.graphics.rectangle("line", nameX, nameY, nameW, nameH, scale * 0.5, scale * 0.5)
        local c = NAME_COLORS[line.speaker] or {1, 0.92, 0.68}
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.print(line.speaker, nameX + pad, nameY + scale * 0.4)
    end

    -- text
    love.graphics.setFont(fonts.dialogue)
    love.graphics.setColor(0.97, 0.95, 0.90, 1)
    local textW = boxX + boxW - pad - textX
    love.graphics.printf(line.text:sub(1, math.floor(self.shown)), textX, boxY + pad, textW, "left")

    -- continue marker
    if self.shown >= #line.text and math.floor(self.blink * 2.5) % 2 == 0 then
        local mx = boxX + boxW - pad * 1.5
        local my = boxY + boxH - pad * 1.2
        love.graphics.setColor(0.93, 0.84, 0.62, 1)
        love.graphics.polygon("fill", mx - scale * 2, my - scale * 1.5, mx + scale * 2, my - scale * 1.5, mx, my + scale * 0.5)
    end

    love.graphics.setLineWidth(1)
    setWhite()
end
