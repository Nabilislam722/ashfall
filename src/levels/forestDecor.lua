-- The forest's scenery (maps/_tilesets/forest/Objects.png): in a map, trees,
-- bushes, rocks, ruins, logs, mushrooms and reeds are painted with the "Objects"
-- tileset into tile layers named "Props..." (as many as needed, so pictures can
-- overlap). They aren't drawn as tiles: each picture (tiles that sit side by
-- side both on the map and on the sheet) becomes one piece of scenery,
-- depth-sorted against the hero, the slimes and everyone else, with a collider
-- at its foot that suits what it is: a tree's trunk, a boulder's base...
-- (The Whispering Woods, maps/woods.tmx, is built this way.)

forestDecor = { props = {} }

-- what each tile of the Objects sheet (32 x 33 tiles, row by row) belongs to:
-- T tree, S sapling, B bush, L fallen log, U stump, R ruin, O boulder,
-- N stone, K dark rock, P pebble, M mushroom, E reeds, . nothing
local KINDS = ""
    .. ".TTT.TTTTTTTT.....TTTT..TTTBBBBB"
    .. "TTTTTTTTTTTTTSSSSTTTTTTTTTTBBBBB"
    .. "TTTTTTTTTTTTTSSSSTTTTTTTTTTBBBBB"
    .. "TTTTTTTTTTTTT.SSSTTTTT.TTTTBBBBB"
    .. ".TTT.TTTTTTTT...TTTTTT.TTTTBB..."
    .. ".TTTTTTTTTTT...TTTTBBBTTTTTBBBB."
    .. ".TTTTTTTTTTTSSSTTTTBBBTTTTT.BBB."
    .. ".TTTTTTTTTTTSSSTTTTBBBTTTTT.BBB."
    .. ".TTTTTTTTTT.SSSTTT.BB.TTTTTBBB.."
    .. ".....LLUUUSSS.SSLLLUUUUUUSSBBB.."
    .. "..LLLLLUUUSSS.SSLLLUUUUUUSSBBB.."
    .. ".LLLLLLUUUSSS.SS.....OOOOOOOOOO."
    .. "....RRR.RRRR..RR.RRR.OOOOOOOOOO."
    .. "...RRRRRRRRRRRRRRRRR.OOOOOOOOOO."
    .. "..RRRRRRRRRRRRRRRRRR.OOOO......."
    .. ".RRRRRRRRRRR.RRRR....OOOOOOOOOO."
    .. ".RRRRRRRRRRR..RR.....OOOOOOOOOO."
    .. ".RRRRRR.RR.PP.RR.RRR.OOOOOOOOOO."
    .. "...RRRRRRRRPPRRRRRRR.OOOONNNNN.."
    .. "....RRR.RRRR.RRRRRRR.NNNNNNNNN.."
    .. "...RRRRRRRRRRRRRR..NNNNNNNNNNN.."
    .. "..RRRRRRRRRRRNNNNNNNNNNNNNN....."
    .. ".RRRRRRRRRRR.NNNNNNNNNNNN......."
    .. ".RRRRRRRRRRR.NNNNNNNN..MMMMMM..."
    .. ".RRRRRR.RR.PPNNN.......MMMMMM..."
    .. "...RRRR.RR.PP..........MMMMMM..."
    .. ".KKKKKKKKKKKKKKKKKKKK..MMMMMM..."
    .. ".KKKKKKKKK.KKKKKKKKK............"
    .. ".KKK.......KKK.....EE.EEEEE....."
    .. "..EE.E...EEE.EE.EE.EE.EE.E......"
    .. ".EEEEEEEEEEE.EE.EE.EE.EE..E....."
    .. ".EE..EE.E..........EE.EE.EE....."
    .. "...................EE.EE.E......"
local PRIORITY = "TROSLUBKNMEP" -- a picture is the first of these it has tiles of
local COLUMNS = 32

function forestDecor.isPropLayer(layer)
    return layer.type == "tilelayer" and layer.name:sub(1, 5) == "Props"
end

-- where each tile of the sheet is actually drawn (alpha over 100): four hex
-- digits per tile, the first and last column and row with pixels ("----": none)
local BOUNDS = ""
    .. "----18ff05ff069f----baff02ff02ff0b6f87ff02ff01ff06af--------------------68ff03ff04ff095f--------04ff02ff058f9bff06ff0b8f32ff03cf"
    .. "94fe00ff00ff00ff016f20ff00ff00ff00df30ff00ff00ff00cfddff03ff01ff092fb7ff00ff00ff00ff00ff092f30ff00ff00ff00cf60ff00ff009f20fc00cc"
    .. "51ff00ff00ff00ff00bf10ff00ff00ff00ff10ff00ff00ff00efc0fd00ff00ff004fb0f800ff00ff00ff00ff002d30ff00ff00ff00bf80f600f7006533ff02df"
    .. "90fa00ff00ff00ff00ac40ff00ff00ff00ed40f700ff00ff00da----30fa00fa0000e2f600ff00ff00ff00cf----90ff00ff00ff003f57ff088f11df10fd00dd"
    .. "----50fc00fe00dd----c0f800ff00ff005bc0f900fe00fe004a------------eeff0e5f80fb00ff00fe0046----a0f800fc00fc012560f90099------------"
    .. "----a5ff01ff00ff055f56ff02ff058fc8ff01ff00ff074f------------33ff00ff00ff03bfb5ff00ff045f32ff01ff06bf21ff00ef10ff06ff04ff077f----"
    .. "----30ff00ff00ff00cf00ff00ff00ff30ff00ff00ff007f87ff06ff098f30ff00ff00ff00bf90fd00fe007d10ff00ff00ff00ff00ef----50ff00ff008f----"
    .. "----20ff00ff00ff00cf10ff00ff00ef40fc00ff00ff007e40ff00ff00af40ff00ff00ff00bf55ff059f01fe10ff00ff00cf64ff04af----60f600f90097----"
    .. "----b0f200fd00fd0303a0f800fc0068f5f500ff00ff----90f800fc008af0f600fe00fe----30fa00ba----70fd00fe005b60f900a996ff03ff067f--------"
    .. "--------------------35ff04afffff0bff0e1f62ff00ff038f----67ff06cf86ff06ff07bf53ff049f51ff01bf16ff06cf10ff00df60ff00ff009f--------"
    .. "--------20ff02ff02ff00ff00ff50ff00ff009f50ff00ff00bf----30ff00df80fb00f900a710fd00de50fe00ae00fb00cb20ff00ee90f300f70075--------"
    .. "----f3f400f800f620f600f6006880f300f60085c0fb00fe009c----30fa00ba--------------------ccff00ff00ff087fa3ff00ff025ffcff06ff084f----"
    .. "----------------a8ff02ff04bf----a4ff03ff02ff0a8f--------86ff00ff----fcff00ff03bf----60ff00ff00ff007f30ff00ff00af70ff00ff006f----"
    .. "------------10ff00ff00ff00ff0d3f40ff00ff00ff00ff078f77ff00ff00ff088f50ff00ff00ef----30ff00ff00ff00af40fa00fe009c90f200f70044----"
    .. "--------a8ff00ff00ff00ff00ff005f40ff00ff00ff00ff00ea30ff00ff00ff00ef70fc00ff00cd----a0f600fc00fe0054----------------------------"
    .. "----b5ff00ff00ff00ff00ff00ff00ff40ff00ff00ff009f----60fb00ff00ff00a7----------------ccff00ff00ff087fa3ff00ff025ffcff06ff084f----"
    .. "----60ff00ff01ff00ff00ff00ff003dc0f400fb00fb00a9--------b0b00050--------------------60ff00ff00ff007f40ff00ff009f80ff00ff005f----"
    .. "----d0f600fd00ff00ff00ff00ff----02ff00df----87ff077f----86ff00ff----fcff00ff03bf----50ff00ff00ff009f60f900fc009bb0f200f50032----"
    .. "------------00fa00f800fd00e9f0f500ff00ff020670f8008877ff00ff00ff089f50ff00ff00ef----90f400fa00fb003258ff0a6f79ff09ff0b8f--------"
    .. "----------------a8ff02ff04bf----a4ff03ff02ff0a8f----40ff00ff00ff00ef60fd00ff00dd----55ff03ef4aff09cf70f6007770fe00ff008f--------"
    .. "------------10ff00ff00ff00ff0d3f40ff00ff00ff00ff078f50fb00ff00ff00b5--------a9ff098f10fd00be30fa00cc8aff085fe0f600e80061--------"
    .. "--------b8ff00ff00ff00ff00ff005f40ff00ff00ff00ff00e945ff03df7aff09bf01ff03ff90f900a946ff068fabff0c4f90f40011--------------------"
    .. "----c6ff00ff00fe00ff00ff00ff00ff50ff00ff00ff009f----10fb009c60f900aa40ff00fe99ff0a5f50f90095b0f20031----------------------------"
    .. "----80ff00ff01ff00ff00ff00ff0032d0f500f900f90098----56ff068f01ff34fc21fe01ff60f70067--------75ff05df84ff046f86ff065f------------"
    .. "----c0f700fc00ff00ff00ff00ff----12ff00cf----87ff076f50f8008623de----------------------------60fc00dd50f900bc90f70078------------"
    .. "------------10f900f800fd00f8----00fe00ff----80f60066----------------------------------------52ff02af54ff04cf86ff076f------------"
    .. "----cfdf39ff0d4f00ff00ff65ff06bf88ff098f14decfdf39ff0d4f10ff00ef75ff06afa8ff098f14dd--------30fb00ab50f800d850f90068------------"
    .. "----10ff00ff008f20fc00ec30fb00dc60f80098----20ff00ff008f20fb00eb40fa00db70f70087------------------------------------------------"
    .. "----60f600fb0074----------------------------50f700fa0074--------------------03ff017f----22ff068ffcfd04ff0225--------------------"
    .. "--------deff0f0f----0f0f------------1f2f28ff049f----45af195f----1aff054f----00fd0036----40fb0078----10db------------------------"
    .. "----d4ff00ff004df0fa00ff035ff9fa01ff001220ff007d----40fe00ac----10fe0000----5ebf097f----6abf6e7f--------1a6f--------------------"
    .. "----f0f000ea--------30f80011----20c8----------------------------------------40ff00bf----60ff00cf----34ff003d--------------------"
    .. "----------------------------------------------------------------------------a0f50034----d0f20043----90e3------------------------"

-- the collider for a picture of `kind` whose pixels cover x0, y0, w, h, or nil:
-- what really stands in the way, where it's drawn (a tree's trunk where it
-- meets the roots, the body of a stump or a boulder; ruins have their own,
-- RUINS below); bushes,
-- small stones, mushrooms and reeds can be walked through
local function collider(kind, x0, y0, w, h)
    local bottom, cx = y0 + h, x0 + w / 2
    if kind == "T" then
        local cw = math.max(12, math.min(18, w * 0.2))
        return cx - cw / 2, bottom - 12, cw, 9
    elseif kind == "S" then
        return cx - 4, bottom - 9, 8, 6
    elseif kind == "L" then
        return x0 + 4, y0 + h * 0.3, w - 8, h * 0.55
    elseif kind == "U" then
        return x0 + w * 0.15, y0 + h * 0.3, w * 0.7, h * 0.6
    elseif kind == "R" then
        return x0 + w * 0.2, bottom - h * 0.35, w * 0.6, h * 0.3
    elseif kind == "O" then
        return x0 + w * 0.1, y0 + h * 0.35, w * 0.8, h * 0.55
    elseif kind == "N" or kind == "K" then
        if w >= 40 then return x0 + w * 0.15, y0 + h * 0.35, w * 0.7, h * 0.5 end
    end
end

-- ruins stand on their stones: boxes under each stone's base (and the trunks
-- grown through them), in px from the top-left of the ruin's tile box (at, in
-- tiles) on the sheet; the grass between the stones and the canopies above can
-- be walked under. A ruin is known by the sheet tiles that are its own.
local RUINS = {
    -- the ring of standing stones
    { at = { 1, 12 }, tiles = { 388, 389, 390, 419, 420, 421, 422, 423, 450, 451, 452, 453, 454, 455, 481, 482, 483, 484, 485, 486, 487, 513, 514, 515, 516, 517, 518, 519, 545, 546, 547, 548, 549, 550, 579, 580, 581, 582, 583 },
      boxes = { { 11, 79, 16, 10 }, { 18, 50, 18, 9 }, { 33, 42, 10, 9 }, { 48, 45, 9, 6 }, { 34, 88, 34, 13 }, { 66, 96, 8, 10 }, { 64, 38, 12, 10 }, { 83, 80, 13, 11 }, { 77, 44, 8, 8 } } },
    -- the ring, with its shadow
    { at = { 1, 19 }, tiles = { 612, 613, 614, 643, 644, 645, 646, 647, 674, 675, 676, 677, 678, 679, 705, 706, 707, 708, 709, 710, 711, 737, 738, 739, 740, 741, 742, 743, 769, 770, 771, 772, 773, 774, 803, 804, 805, 806 },
      boxes = { { 11, 79, 16, 10 }, { 18, 50, 18, 9 }, { 33, 42, 10, 9 }, { 48, 45, 9, 6 }, { 34, 88, 34, 13 }, { 66, 96, 8, 10 }, { 64, 38, 12, 10 }, { 83, 80, 13, 11 }, { 77, 44, 8, 8 } } },
    -- the tumbled heap
    { at = { 8, 12 }, tiles = { 392, 393, 394, 395, 424, 425, 426, 427, 428, 456, 457, 458, 459, 460, 488, 489, 490, 491, 520, 521, 522, 523 },
      boxes = { { 12, 60, 13, 12 }, { 28, 26, 36, 20 }, { 65, 31, 11, 7 }, { 27, 62, 12, 11 }, { 40, 57, 15, 11 } } },
    -- the heap, with its shadow
    { at = { 8, 19 }, tiles = { 616, 617, 618, 619, 648, 649, 650, 651, 652, 680, 681, 682, 683, 684, 712, 713, 714, 715, 744, 745, 746, 747 },
      boxes = { { 12, 60, 13, 12 }, { 28, 26, 36, 20 }, { 65, 31, 11, 7 }, { 27, 62, 12, 11 }, { 40, 57, 15, 11 } } },
    -- a broken pillar
    { at = { 7, 17 }, tiles = { 552, 553, 584, 585, 586 },
      boxes = { { 21, 19, 26, 11 } } },
    -- a stump of wall
    { at = { 8, 24 }, tiles = { 776, 777, 808, 809 },
      boxes = { { 4, 19, 25, 10 } } },
}
local RUIN_OF = {}
for _, ruin in ipairs(RUINS) do
    for _, id in ipairs(ruin.tiles) do RUIN_OF[id] = ruin end
end

-- a ruin's boxes on the map, if this picture is one
local function ruinBoxes(cells, tw, th)
    for _, c in ipairs(cells) do
        local ruin = RUIN_OF[c.id]
        if ruin then
            local ox = (c.x - 1) * tw - (c.id % COLUMNS) * tw
            local oy = (c.y - 1) * th - math.floor(c.id / COLUMNS) * th
            local boxes = {}
            for _, b in ipairs(ruin.boxes) do
                table.insert(boxes, { ruin.at[1] * tw + b[1] + ox, ruin.at[2] * th + b[2] + oy, b[3], b[4] })
            end
            return boxes
        end
    end
end

forestDecor.KIND_NAMES = { T = "tree", S = "sapling", B = "bush", L = "log", U = "stump", R = "ruin", O = "boulder",
    N = "stone", K = "rock", P = "pebble", M = "mushroom", E = "reeds", ["."] = "?" }

-- the pictures in one Props layer
local function gather(self, map, layer, sheet)
    local first, count = sheet.firstgid, sheet.tilecount
    local function local_(x, y)
        local row = layer.data[y]
        local tile = row and row[x]
        if tile and tile.gid >= first and tile.gid < first + count then return tile.gid - first, tile end
    end
    local seen = {}
    for y = 1, layer.height do
        for x = 1, layer.width do
            local id = local_(x, y)
            if id and not seen[y * 10000 + x] then
                -- flood out to the neighbours that continue the same picture
                local cells, stack = {}, { { x, y } }
                seen[y * 10000 + x] = true
                while #stack > 0 do
                    local cx, cy = unpack(table.remove(stack))
                    local cid, tile = local_(cx, cy)
                    table.insert(cells, { x = cx, y = cy, id = cid, quad = tile.quad })
                    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local nx, ny = cx + d[1], cy + d[2]
                        local nid = local_(nx, ny)
                        if nid and not seen[ny * 10000 + nx] and nid == cid + d[1] + d[2] * COLUMNS
                            and cid % COLUMNS + d[1] >= 0 and cid % COLUMNS + d[1] < COLUMNS then
                            seen[ny * 10000 + nx] = true
                            table.insert(stack, { nx, ny })
                        end
                    end
                end
                self:add(map, sheet, cells)
            end
        end
    end
end

function forestDecor:add(map, sheet, cells)
    local tw, th = map.tilewidth, map.tileheight
    -- the picture's drawn pixels, from each tile's bounds
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local has = {}
    for _, c in ipairs(cells) do
        has[KINDS:sub(c.id + 1, c.id + 1)] = true
        local b = BOUNDS:sub(c.id * 4 + 1, c.id * 4 + 4)
        if b ~= "----" then
            local tx, ty = (c.x - 1) * tw, (c.y - 1) * th
            minX = math.min(minX, tx + tonumber(b:sub(1, 1), 16))
            minY = math.min(minY, ty + tonumber(b:sub(2, 2), 16))
            maxX = math.max(maxX, tx + tonumber(b:sub(3, 3), 16) + 1)
            maxY = math.max(maxY, ty + tonumber(b:sub(4, 4), 16) + 1)
        end
    end
    if minX == math.huge then return end -- nothing drawn
    local kind = "."
    for i = 1, #PRIORITY do
        local k = PRIORITY:sub(i, i)
        if has[k] then kind = k break end
    end
    local x0, y0, w, h = minX, minY, maxX - minX, maxY - minY
    local prop = { image = sheet.image, cells = {}, kind = kind, x = x0, y = y0, w = w, h = h, sortY = maxY - 3 }
    for _, c in ipairs(cells) do
        table.insert(prop.cells, { quad = c.quad, x = (c.x - 1) * tw, y = (c.y - 1) * th })
    end
    local boxes = ruinBoxes(cells, tw, th)
    if not boxes then
        local cx, cy, cw, ch = collider(kind, x0, y0, w, h)
        boxes = cx and { { cx, cy, cw, ch } } or {}
    end
    -- it sorts at the foot of its lowest box
    for i, b in ipairs(boxes) do
        local wall = spawnWall(b[1], b[2], b[3], b[4])
        if wall then wall.scenery = true end
        prop.sortY = i == 1 and b[2] + b[4] or math.max(prop.sortY, b[2] + b[4])
    end
    table.insert(self.props, prop)
end

function forestDecor:setMap(map)
    self.props = {}
    if not map then return end
    local sheet
    for _, ts in ipairs(map.tilesets) do
        if ts.name == "Objects" then sheet = ts end
    end
    if not sheet then return end
    for _, layer in ipairs(map.layers) do
        if forestDecor.isPropLayer(layer) then gather(self, map, layer, sheet) end
    end
end

local function drawProp(prop)
    for _, c in ipairs(prop.cells) do
        love.graphics.draw(prop.image, c.quad, c.x, c.y)
    end
end

-- each piece of scenery, for the depth-sorted world (src/draw.lua)
function forestDecor:collect(items)
    for _, prop in ipairs(self.props) do
        table.insert(items, { y = prop.sortY, draw = drawProp, arg = prop })
    end
end
