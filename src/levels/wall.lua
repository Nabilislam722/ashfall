walls = {}

function spawnWall(x, y, width, height, name, type, parent)

    -- Do not spawn the wall if the name is in data.breakables
    if data.breakables[name] then return end

    local wall = world:newRectangleCollider(x, y, width, height, {collision_class = "Wall"})
    wall:setType('static')
    wall.dead = false
    wall.offY = 0
    wall.name = name
    wall.parent = parent
    wall.type = type
    wall.rect = { x = x, y = y, w = width, h = height } -- used by the minimap

    if name and name:startswith('break') then
        wall.breakable = true

        -- an example of a name is 'breakRock1', where Rock tells us the sprite
        -- (or the type does: the meadow's cave keeps its old name, breakWall1,
        -- so saves that already opened it stay open, but is sealed by a rock)
        if name:find("Rock") or type == "rock" then
            wall.sprite = sprites.environment.breakableRock
            function wall:onBreak()
                data.breakables[self.name] = true
                particleEvent("rockBreak", x+width/2, y+height/2)
            end
        elseif name:find("Wall") then
            wall.sprite = sprites.environment.breakableWall
            wall.offY = -8
            function wall:onBreak()
                data.breakables[self.name] = true
                particleEvent("rockBreak", x+width/2, y+height/2)
            end
        elseif name:find("Door") then
            wall.sprite = sprites.environment.lockedDoor
            wall.offY = -4
            wall.type = "lockedDoor"

            function wall:onBreak()
                data.breakables[self.name] = true
                shake:start(0.1, 1, 0.03)
            end
        end
    end

    if wall.type then
        if wall.type == 'ground' then
            wall:setCollisionClass('Ground')
        end
    end

    table.insert(walls, wall)
    return wall

end

-- removes a wall that was spawned while the map is running (e.g. a fence that drops)
function removeWall(wall)
    for i = #walls, 1, -1 do
        if walls[i] == wall then
            wall:destroy()
            table.remove(walls, i)
            return
        end
    end
end

function walls:update(dt)
    local i = #walls
    while i > 0 do
        if walls[i].dead then
            if walls[i].onBreak then walls[i]:onBreak() end
            walls[i]:destroy()
            table.remove(walls, i)
        end
        i = i - 1
    end
end

function walls:draw()
    -- most walls are invisible colliders, but some have sprites
    for _,w in ipairs(walls) do
        if w.sprite then
            love.graphics.draw(w.sprite, w:getX(), w:getY() + w.offY, nil, nil, nil, w.sprite:getWidth()/2, w.sprite:getHeight()/2)
        end
    end
end
