-- Handles the player running out of hearts: fade out, then return to the
-- spot where they last entered the current map with full health.

respawn = {}
respawn.map = "test"
respawn.x = 384
respawn.y = 310
respawn.pending = false
respawn.timer = 0
respawn.justRevived = false

-- remembers where the player came into a map; called on every map change
function respawn:record(mapName, x, y)
    self.map = mapName
    self.x = x
    self.y = y
end

function respawn:update(dt)
    if gamestate ~= 1 or godMode then return end
    if lairStory.spare then return end -- Gula's onslaught: hearts can hit zero, but nobody dies

    if self.pending then
        if self.timer > 0 then
            self.timer = self.timer - dt
            if self.timer <= 0 then
                curtain:call(self.map, self.x, self.y, "fade")
            end
        end
        return
    end

    if player.health <= 0 and curtain.state == 0 then
        self.pending = true
        self.timer = 1.1
        player.health = 0
        player:setLinearVelocity(0, 0)
        shake:start(0.25, 2.5, 0.03)
        particleEvent("death", player:getX(), player:getY())
        dj.play(sounds.enemies.die, "static", "effect", 1, 0.7)
        showToast("You were knocked out!", 1.6)
    end
end

-- called by triggerTransition once the new map is loaded
function respawn:onArrive()
    if not self.pending then return end
    self.pending = false
    self.justRevived = true
    player.health = data.maxHealth
    player.damagedTimer = 0
    player.stunTimer = 0
end
