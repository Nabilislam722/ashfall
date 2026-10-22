function createCollisionClasses()
    world:addCollisionClass('Ignore', {ignores = {'Ignore'}})
    world:addCollisionClass('Ground', {ignores = {'Ignore'}})
    world:addCollisionClass('Player', {ignores = {'Ignore'}})
    world:addCollisionClass('Wall', {ignores = {'Ignore'}})
    world:addCollisionClass('Transition', {ignores = {'Ignore'}})
    world:addCollisionClass('Enemy', {ignores = {'Ignore', 'Player'}})
    world:addCollisionClass('Projectile', {ignores = {'Ignore', 'Enemy', 'Player', 'Ground', 'Transition'}})
    world:addCollisionClass('NPC', {ignores = {'Ignore', 'Enemy', 'Projectile', 'Transition', 'NPC'}})
    world:addCollisionClass('FreePlayer', {ignores = {'Wall', 'Enemy', 'Projectile', 'NPC'}})

    particleWorld:addCollisionClass('Particle', {ignores = {'Particle'}})
end