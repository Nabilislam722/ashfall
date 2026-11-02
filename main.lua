function love.load()
    math.randomseed(os.time())

    d1 = 0
    d2 = 0

    require("src/startup/gameStart")
    gameStart()
    createNewSave()

    settings:load() -- the player's volume, keys and so on (src/utilities/settings.lua)
    loadMap("menu")
    menu:open()

end

function love.update(dt)
    -- a button let go while the window wasn't looking still counts as up
    for b, held in pairs(mouseHeld) do
        if held and not love.mouse.isDown(b) then mouseHeld[b] = false end
    end
    intro:update(dt) -- the New Game intro, and its music fading on into the game (src/ui/intro.lua)
    updateAll(dt * devTools:timeScale())
end

function love.draw()
    if intro.active then
        intro:draw()
        return
    end
    drawBeforeCamera()

    cam:attach()
        drawCamera()
    cam:detach()

    drawAfterCamera()

    local debug = require "src/debug"
    --debug:d()
    --debug:single()
end

-- a key held down sends repeats on some platforms (and the browser): only a fresh press acts
function love.keypressed(key, scancode, isrepeat)
    if isrepeat then return end
    -- any key skips the intro
    if intro.active then
        intro:skip()
        return
    end
    -- Settings open: it has the keys (src/ui/settingsMenu.lua)
    if settingsMenu.active then
        settingsMenu:keypressed(key)
        return
    end
    -- the Adventure Book open: it has the keys (src/ui/book.lua)
    if book.active then
        book:keypressed(key)
        return
    end
    -- F3: the developer panel (and, while it's open, its number keys)
    if devTools:keypressed(key) then
        return
    end

    -- F11 (or Backspace): fullscreen on and off on desktop (in the browser, Settings and the title screen do it)
    if (key == 'f11' or (key == 'backspace' and not menu:modal())) and love.system.getOS() ~= "Web" then
        toggleFullscreen()
        return
    end

    -- title screen: Continue / New Game / Settings (Esc quits, on desktop)
    if gamestate == 0 then
        if key == 'escape' and not menu:modal() then
            if love.system.getOS() ~= "Web" then love.event.quit() end
            return
        end
        menu:keypressed(key)
        return
    end

    if gamestate ~= 1 then return end
    -- conversations, trading and cutscenes take the keyboard first
    if dialogue.active then
        dialogue:keypressed(key)
        return
    end
    if shop.active then
        shop:keypressed(key)
        return
    end
    if hemiExchange.active then
        hemiExchange:keypressed(key)
        return
    end
    if manaWell.active then
        manaWell:keypressed(key)
        return
    end
    if vsBanner.active then
        vsBanner:skip()
        return
    end
    if cutscene.active or respawn.pending then
        return
    end

    -- Esc closes the item menu, or opens Settings (as the Settings button does)
    if key == 'escape' then
        if pause.active then pause:toggle() elseif curtain.state == 0 then settingsMenu:open("game") end
        return
    end

    -- the other actions, on the player's keys (src/utilities/controls.lua)
    if controls:is("minimap", key) then
        settings:toggleMinimap()
        return
    end
    -- the Adventure Book (at its journal)
    if (controls:is("book", key) or controls:is("journal", key)) and not pause.active and not isPlayerFrozen() and curtain.state == 0 then
        book:open(controls:is("journal", key) and not controls:is("book", key) and "journal" or nil)
        return
    end
    if controls:is("shadowStep", key) then
        player:shadowStep()
        return
    end
    if controls:is("roll", key) then
        player:roll()
        return
    end
    local interact, fire, items = controls:is("interact", key), controls:is("fireball", key), controls:is("items", key)
    if interact or fire or items then
        -- the item menu open: any of these closes it (and casts nothing)
        if pause.active then
            pause:toggle()
            return
        end
        -- talk to a villager close by, or save at a checkpoint
        if interact and (npcs:tryInteract() or checkpoints:tryInteract()) then
            return
        end
        -- with no one to talk to, the fireball (tapped, a fireball; held, it
        -- charges: src/spells/fireball.lua); else the item menu
        if fire then
            fireballs:press()
        elseif items then
            pause:toggle()
        end
        return
    end
    if controls:is("zoomIn", key) then
        setZoomLevel(zoomLevel + 0.1)
    elseif controls:is("zoomOut", key) then
        setZoomLevel(zoomLevel - 0.1)
    elseif controls:is("zoomReset", key) then
        setZoomLevel(settings.values.zoom) -- (the zoom chosen in Settings)
    end
end

function love.wheelmoved(x, y)
    if settingsMenu.active then
        settingsMenu:wheelmoved(y)
        return
    end
    if gamestate ~= 1 or pause.active or book.active or y == 0 then return end
    setZoomLevel(zoomLevel + y * 0.1)
end

function love.keyreleased(key)
    if pause.active or isPlayerFrozen() then return end
    if key == 'z' then
        useItem('z', true)
    elseif key == 'x' then
        useItem('x', true)
    end
end

mouseHeld = {} -- the mouse buttons down right now

-- Settings' and the title screen's buttons light up under the mouse
function love.mousemoved(x, y)
    if intro.active then return end
    if settingsMenu.active then
        settingsMenu:mousemoved(x, y)
    elseif gamestate == 0 then
        menu:mousemoved(x, y)
    end
end

function love.mousepressed( x, y, button )
    if intro.active then
        intro:skip()
        return
    end
    if settingsMenu.active then
        settingsMenu:mousepressed(x, y, button)
        return
    end
    if book.active then
        book:mousepressed(x, y, button)
        return
    end
    if gamestate == 0 then
        menu:mousepressed(x, y, button)
        return
    end
    if gamestate == 1 then
        if dialogue.active then
            if button == 1 then dialogue:advance() end
            return
        end
        if shop.active then
            shop:mousepressed(x, y, button)
            return
        end
        if hemiExchange.active then
            hemiExchange:mousepressed(x, y, button)
            return
        end
        if manaWell.active then
            manaWell:mousepressed(x, y, button)
            return
        end
        if vsBanner.active then
            vsBanner:skip()
            return
        end
        if cutscene.active or respawn.pending then
            return
        end
        if settingsButton:mousepressed(x, y, button) then
            return
        end
    end

    -- one press, one action: a button only counts again once it has come back up
    -- (a second "down" without an "up" between is a duplicate event, not a press)
    if mouseHeld[button] then return end
    mouseHeld[button] = true
    if button == 1 then
        if pause.active then
            pause:equip('left')
        else
            useItem('left')
        end
    elseif button == 2 then
        if pause.active then
            pause:equip('right')
        else
            useItem('right')
        end
    end
end

function love.mousereleased( x, y, button )
    mouseHeld[button] = false
    if isPlayerFrozen() then return end
    if button == 1 then
        if pause.active then
            --pause:equip('z')
        else
            useItem('z', true)
        end
    elseif button == 2 then
        if pause.active then
            --pause:equip('x')
        else
            useItem('x', true)
        end
    end
end
