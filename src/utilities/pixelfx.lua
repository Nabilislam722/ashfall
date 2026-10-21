-- Pixel art for effects drawn with shapes (circles, rings, lines, glows), so they
-- match the sprites instead of being drawn smooth at the screen's resolution.
--
-- pixelfx.world(draw)   with the camera attached: whatever draw() draws (in world
--                       coordinates) lands on a small canvas with one texel per
--                       pixel of the game's art, and is then blown back up onto
--                       the scene with hard edges
-- pixelfx.screen(draw)  the same for things drawn in screen coordinates (the
--                       pixels are the same size on screen as the sprites')
-- pixelfx.size()        how many screen pixels one art pixel covers
--
-- A circle comes out as a stepped pixel circle and a line as a line of whole
-- pixels (inside, no line is thinner than one art pixel); soft glows and
-- see-through shapes come out as a few steps of brightness, ordered-dithered
-- like old pixel art. Normal and additive drawing both work: the canvas holds
-- premultiplied colour, and what is drawn additively carries no alpha of its
-- own, so it adds to the scene when the canvas goes on.

pixelfx = {}

local LEVELS = 6 -- steps of brightness a glow or a see-through shape comes out in

local canvases = {} -- one per nesting depth (a pass may happen inside another's drawing)
local depth = 0
local shader = nil
local setLineWidth = love.graphics.setLineWidth
local minWidth = 0

local SHADER = [[
extern vec2 size;      // the canvas, in texels
extern number levels;  // steps of brightness
// an ordered-dither threshold (4x4 Bayer) for texel a
float bayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
    vec4 c = Texel(tex, uv);
    float k = max(max(c.r, c.g), max(c.b, c.a));
    if (k <= 0.0) return vec4(0.0);
    // its brightness, rounded to a few steps with a dither between them (hue kept)
    float d = bayer4(floor(uv * size)) - 0.5;
    float q = clamp(floor(k * levels + 0.5 + d) / levels, 0.0, 1.0);
    return c * (q / k) * color;
}
]]

local function clampedLineWidth(width)
    setLineWidth(math.max(width, minWidth))
end

function pixelfx.size()
    return getRenderScale()
end

-- draws through a w x h canvas: drawIn() fills it (canvas transform reset),
-- put(canvas) lays it on the scene in the transform that was current
local function pass(w, h, minW, drawIn, put)
    depth = depth + 1
    local canvas = canvases[depth]
    if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        canvas = love.graphics.newCanvas(w, h)
        canvas:setFilter("nearest", "nearest")
        canvases[depth] = canvas
    end
    if shader == nil then
        local ok, made = pcall(love.graphics.newShader, SHADER)
        shader = ok and made or false
    end

    local prevMin, prevSet = minWidth, love.graphics.setLineWidth
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.setLineStyle("rough")
    minWidth = minW
    love.graphics.setLineWidth = clampedLineWidth
    clampedLineWidth(love.graphics.getLineWidth())
    local ok, err = pcall(drawIn)
    love.graphics.setLineWidth = prevSet
    minWidth = prevMin
    love.graphics.pop()

    if ok then
        love.graphics.push("all")
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(1, 1, 1, 1)
        if shader then
            shader:send("size", { w, h })
            shader:send("levels", LEVELS)
            love.graphics.setShader(shader)
        end
        put(canvas)
        love.graphics.pop()
    end
    depth = depth - 1
    if not ok then error(err, 0) end
end

function pixelfx.world(draw)
    local s = getRenderScale()
    local sw, sh = love.graphics.getDimensions()
    local wx, wy = cam:worldCoords(0, 0)
    -- the canvas covers the view (and a little more), on whole art pixels
    local ox, oy = math.floor(wx) - 2, math.floor(wy) - 2
    local w, h = math.ceil(sw / s) + 5, math.ceil(sh / s) + 5
    pass(w, h, 1, function()
        love.graphics.translate(-ox, -oy)
        draw()
    end, function(canvas)
        love.graphics.draw(canvas, ox, oy)
    end)
end

function pixelfx.screen(draw)
    local s = getRenderScale()
    local sw, sh = love.graphics.getDimensions()
    local w, h = math.ceil(sw / s) + 1, math.ceil(sh / s) + 1
    pass(w, h, s, function()
        love.graphics.scale(1 / s)
        draw()
    end, function(canvas)
        love.graphics.draw(canvas, 0, 0, 0, s, s)
    end)
end
