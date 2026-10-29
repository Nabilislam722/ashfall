function love.load()
    math.randomseed(os.time())

    d1 = 0
    d2 = 0

    require("src/startup/gameStart")
    gameStart()
    createNewSave()

    loadMap("menu")
    menu:open()
 
    dj.volume("effect", 1)

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
    -- the Adventure Book open: it has the keys (src/ui/book.lua)
    if book.active then
        book:keypressed(key)
        return
    end
    -- F3: the developer panel (and, while it's open, its number keys)
    if devTools:keypressed(key) then
        return
    end

    -- title screen: Continue / New Game
    if gamestate == 0 and (menu.confirming or (key ~= 'escape' and key ~= 'backspace')) then
        menu:keypressed(key)
        return
    end

    -- conversations, trading and cutscenes take the keyboard first
    if gamestate == 1 then
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
        if topMenu.open then
            topMenu:keypressed(key)
            return
        end
        if vsBanner.active then
            vsBanner:skip()
            return
        end
        if cutscene.active or respawn.pending then
            return
        end
        if key == 'm' and topMenu:canToggle() then
            topMenu:toggle()
            return
        end
        if key == 'n' then
            minimap.visible = not minimap.visible
            return
        end
        -- B: the Adventure Book (J: at its journal)
        if (key == 'b' or key == 'j') and not pause.active and not isPlayerFrozen() and curtain.state == 0 then
            book:open(key == 'j' and "journal" or nil)
            return
        end
        -- Space (or Q): Shadow Step. Left Shift: roll. R: the flame
        if key == 'space' or key == 'q' then
            player:shadowStep()
            return
        end
        if key == 'lshift' or key == 'rshift' then
            player:roll()
            return
        end
        if key == 'r' then
            useItem('altL')
            return
        end
    end

    if key == 'escape' then
        if pause.active then
            pause:toggle()
        elseif love.system.getOS() ~= "Web" then
            love.event.quit()
        end
        return
    end

    if key == 'backspace' and love.system.getOS() ~= "Web" then
        if fullscreen then
            local newWidth = 1920
            local newHeight = 1080
            local fractionW = love.graphics.getWidth()*0.9
            local fractionH = love.graphics.getHeight()*0.9
            if fractionW < newWidth then
                newWidth = fractionW
            end
            if fractionH < newHeight then
                newHeight = fractionH
            end

            setWindowSize(false, newWidth, newHeight)
        else
            setWindowSize(true)
        end
        reinitSize()
    end

    if key == 'return' or key == 'tab' or key == 'e' then
        if gamestate == 1 then
            -- E / Enter talks to a nearby villager or saves at a checkpoint;
            -- Tab always opens the item menu
            if key ~= 'tab' and not pause.active and (npcs:tryInteract() or checkpoints:tryInteract()) then
                return
            end
            -- with no one to talk to, E is the fireball for now (tapped, a fireball; held,
            -- it charges: src/spells/fireball.lua), and only closes the item menu
            if key == fireballs.KEY and not pause.active then
                fireballs:press()
                return
            end
            pause:toggle()
        end
    end


    if key == '+' or key == '=' then
        setZoomLevel(zoomLevel + 0.1)
    elseif key == '-' then
        setZoomLevel(zoomLevel - 0.1)
    elseif key == '0' then
        setZoomLevel(1)
    end
end

function love.wheelmoved(x, y)
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

function love.mousepressed( x, y, button )
    if intro.active then
        intro:skip()
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
        if topMenu:mousepressed(x, y, button) then
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
