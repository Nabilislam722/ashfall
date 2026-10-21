function updateAll(dt)
    onchain:update(dt)

    --if pause.active == false then
        updateGame(dt)
    --end
    
    pause:update(dt)
    dj.cleanup()
    if gameMap then gameMap:update(dt) end
    checkWindowSize()

end

function updateGame(dt)
    miscUpdate(dt)
    if globalStun > 0 then return end

    flux.update(dt)
    highGround:update(dt)
    updateZoom(dt)

    player:update(dt)
    staff:update(dt)
    world:update(dt)
    walls:update(dt)
    blasts:update(dt)
    effects:update(dt)
    waters:update(dt)
    chests:update(dt)
    arrows:update(dt)
    bombs:update(dt)
    boomerang:update(dt)
    grapple:update(dt)
    fireballs:update(dt)
    flames:update(dt)
    loots:update(dt)
    spawners:update(dt)
    enemies:update(dt)
    enemies:destroyDead()
    projectiles:update(dt)
    trees:update(dt)

    npcs:update(dt)
    checkpoints:update(dt)
    villageStory:update(dt)
    lairStory:update(dt)
    worldClock:update(dt)
    wind:update(dt)
    villageDecor:update(dt)
    cutscene:update(dt)
    domainFx:update(dt)
    vsBanner:update(dt)
    dialogue:update(dt)
    shop:update(dt)
    hemiExchange:update(dt)
    floatTexts:update(dt)
    updateToast(dt)
    respawn:update(dt)

    cam:update(dt)
    shake:update(dt)
    shaders:update(dt)
    triggers:update(dt)
    particles:update(dt)
    particleWorld:update(dt)
end
