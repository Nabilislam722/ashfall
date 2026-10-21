-- a map's tile layers are ground under everyone's feet, drawn in the map's
-- order: all but "Above" (roofs and arches, drawn over everyone), "Test", the
-- forest's "Props" layers (src/levels/forestDecor.lua sorts those with the world)
-- and the structures' layers (src/levels/structures.lua: houses, trees, fences...)
function isGroundLayer(layer)
    return layer.type == "tilelayer" and layer.visible ~= false and layer.name ~= "Above" and layer.name ~= "Test"
        and not forestDecor.isPropLayer(layer) and not structures.isLayer(layer)
end

function drawBeforeCamera()
    menu:draw()
end

function drawCamera()

    if gamestate == 0 then return end
    setWhite()

    for _, layer in ipairs(gameMap.layers) do
        if isGroundLayer(layer) then
            gameMap:drawLayer(layer)
        end
    end

    drawShadows()
    walls:draw()
    effects:draw(-1) -- two layers of effects
    spawners:drawGround()
    villageStory:drawGround()
    lairStory:drawGround()
    staff:drawGround()
    chests:draw(-1)
    bombs:draw()
    boomerang:draw()
    loots:draw()
    arrows:draw(-1)
    fireballs:draw(-1)
    grapple:draw(-1)
    effects:draw(0)
    drawSortedWorld()
    chests:draw(1)
    arrows:draw(1)
    fireballs:draw(1)
    grapple:draw(1)
    enemies:drawBurning()
    spawners:drawAir()
    villageStory:drawAir()
    lairStory:drawAir()
    staff:draw()
    effects:drawDarkMagic()
    blasts:draw()
    projectiles:draw()
    effects:draw(1)
    particles:draw()

    wind:draw()

    -- roofs and arch tops that the player walks behind
    if gameMap.layers["Above"] then
        gameMap:drawLayer(gameMap.layers["Above"])
    end
    lighting:drawGlow()

    if gameMap.dark then
        --love.graphics.setShader(shaders.trueLight)
        --love.graphics.rectangle("fill", -10, -10, 10000, 10000)
        --love.graphics.setShader()
        love.graphics.draw(sprites.effects.darkness, player:getX(), player:getY(), nil, nil, nil, sprites.effects.darkness:getWidth()/2, sprites.effects.darkness:getHeight()/2)
    end

end

function drawPlayer()
    if lairStory.heroDown then
        -- knocked out: lying on the ground
        love.graphics.push()
        love.graphics.translate(player:getX(), player:getY() + 4)
        love.graphics.rotate(math.pi / 2)
        love.graphics.translate(-player:getX(), -(player:getY() + 4))
        player:draw()
        love.graphics.pop()
        return
    end
    player:draw()
end

local function drawTree(t)
    love.graphics.draw(t.sprite, t.x + t.width/2, t.y, nil, nil, nil, t.sprite:getWidth()/2, t.sprite:getHeight()*0.75)
end

local function sortByDepth(a, b)
    if a.y == b.y then return a.order < b.order end
    return a.y < b.y
end

-- Draws everything that stands on the ground in back-to-front order, so the
-- player (and the monsters) can walk behind houses, trees, villagers and Rick.
function drawSortedWorld()
    local items = {}
    villageDecor:collect(items)
    forestDecor:collect(items)
    structures:collect(items)
    enemies:collect(items)
    npcs:collect(items)
    signs:collect(items)
    checkpoints:collect(items)
    villageStory:collect(items)
    lairStory:collect(items)
    for _, t in ipairs(trees) do
        table.insert(items, { y = t.y + 10, draw = drawTree, arg = t })
    end
    table.insert(items, { y = player:getY() + 6, draw = drawPlayer })

    for i, item in ipairs(items) do
        item.order = i
    end
    table.sort(items, sortByDepth)

    for _, item in ipairs(items) do
        item.draw(item.arg)
    end
    setWhite()
end

function drawAfterCamera()
    if gamestate ~= 0 then
        lighting:drawDarkness()
        lairStory:drawEmissive()
        staff:drawEmissive()
        -- the developer helpers (F3), over the darkness so they read in dungeons
        cam:attach()
        devTools:drawWorld()
        cam:detach()
        domainFx:drawVoid()
        domainFx:drawFrost()
        floatTexts:draw()
        -- during cinematic scenes (black bars) the HUD steps aside
        if not domainFx:cinematic() then
            npcs:drawOverlay()
            signs:drawOverlay()
            checkpoints:drawOverlay()
            drawHUD()
            villageStory:drawHUD()
            lairStory:drawHUD()
            drawToastAndObjective()
            minimap:draw()
            topMenu:draw()
        end
        vsBanner:draw()
        domainFx:draw()
        domainFx:drawBars()
        dialogue:draw()
        shop:draw()
        hemiExchange:draw()
        manaWell:draw()
        domainFx:drawEyes()
        domainFx:drawCutIn()
        domainFx:drawChains()
        domainFx:drawShouts()
        pause:draw()

        devTools:drawScreen()
    end

    curtain:draw()
end
