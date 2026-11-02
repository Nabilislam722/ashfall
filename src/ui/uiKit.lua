-- The drawing pieces the title screen (src/ui/menu.lua) and Settings
-- (src/ui/settingsMenu.lua) share: panels with their corners cut, soft glows,
-- diamonds, small tags and the buttons, in the game's ember colours.

uiKit = {}
uiKit.ORANGE = { 1, 0.42, 0.1 }
uiKit.GOLD = { 1, 0.84, 0.36 }
uiKit.CREAM = { 1, 0.95, 0.88 }
uiKit.MUTED = { 0.8, 0.76, 0.7 }

function uiKit.setColor(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- a soft glow: rings fading out (additive; more rings for a big one, so it doesn't band)
function uiKit.glow(x, y, rx, ry, rgb, strength, rings)
    rings = rings or 6
    love.graphics.setBlendMode("add")
    for ring = 1, rings do
        local k = ring / rings
        love.graphics.setColor(rgb[1], rgb[2], rgb[3], strength / rings)
        love.graphics.ellipse("fill", x, y, rx * k, ry * k)
    end
    love.graphics.setBlendMode("alpha")
end

-- the same, darkening
function uiKit.shade(x, y, rx, ry, strength, rings)
    for ring = 1, rings do
        local k = ring / rings
        love.graphics.setColor(0.02, 0.01, 0.02, strength / rings)
        love.graphics.ellipse("fill", x, y, rx * k, ry * k)
    end
end

function uiKit.diamond(x, y, r)
    love.graphics.polygon("fill", x, y - r, x + r, y, x, y + r, x - r, y)
end

-- a panel with its corners cut, in the game's pixel look
function uiKit.panel(mode, x, y, w, h, c)
    love.graphics.polygon(mode, x + c, y, x + w - c, y, x + w, y + c, x + w, y + h - c, x + w - c, y + h, x + c, y + h, x, y + h - c, x, y + c)
end

-- a button: dark, with an orange edge that lights up (and glows, and gets a
-- diamond at either end) when it's the one chosen; t: the clock, for the pulse
function uiKit.button(x, y, bw, bh, selected, t)
    local c = math.floor(scale * 1.6)
    local lw = math.max(2, math.floor(scale * 0.45))
    local pulse = 0.5 + 0.5 * math.sin((t or 0) * 4)
    if selected then uiKit.glow(x + bw / 2, y + bh / 2, bw * 0.62, bh * 1.2, uiKit.ORANGE, 0.14 + 0.05 * pulse) end
    love.graphics.setColor(0.07, 0.045, 0.05, selected and 0.93 or 0.8)
    uiKit.panel("fill", x, y, bw, bh, c)
    love.graphics.setColor(1, 0.85, 0.6, selected and 0.1 or 0.04) -- (a lighter rim along the top)
    love.graphics.rectangle("fill", x + c, y + lw, bw - 2 * c, lw)
    love.graphics.setLineWidth(lw)
    if selected then uiKit.setColor(uiKit.ORANGE, 1) else love.graphics.setColor(0.62, 0.42, 0.28, 0.55) end
    uiKit.panel("line", x, y, bw, bh, c)
    if selected then
        uiKit.setColor(uiKit.GOLD, 1)
        local r = scale * (1.1 + 0.25 * pulse)
        uiKit.diamond(x + 4.5 * scale, y + bh / 2, r)
        uiKit.diamond(x + bw - 4.5 * scale, y + bh / 2, r)
    end
end

-- a small tag ending at `right` ("ON" / "OFF", a key); returns its left edge and width
function uiKit.tag(text, right, cy, fill, ink)
    local f = fonts.menuSmall
    love.graphics.setFont(f)
    local tw, th = f:getWidth(text) + 3 * scale, f:getHeight() + 0.6 * scale
    local x, y = right - tw, cy - th / 2
    uiKit.setColor(fill, fill[4] or 1)
    uiKit.panel("fill", x, y, tw, th, math.floor(scale * 0.8))
    uiKit.setColor(ink, 1)
    love.graphics.print(text, x + 1.5 * scale, y + 0.3 * scale)
    return x, tw
end
