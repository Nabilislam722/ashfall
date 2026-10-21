sprites = {}
sprites.playerSheet = love.graphics.newImage('sprites/player/playerSheet.png')
sprites.playerShadow = love.graphics.newImage('sprites/player/playerShadow.png')
sprites.effects = {}
sprites.effects.darkness = love.graphics.newImage('sprites/effects/darkness-wide.png')
sprites.effects.slice = love.graphics.newImage('sprites/effects/slice.png')
sprites.effects.sliceAnim = love.graphics.newImage('sprites/effects/sliceAnim.png')
sprites.effects.explosion = love.graphics.newImage('sprites/effects/explosion.png')
sprites.effects.rock = love.graphics.newImage('sprites/effects/rock.png')
sprites.effects.fuseSmoke = love.graphics.newImage('sprites/effects/fuseSmoke.png')
sprites.effects.scorch = love.graphics.newImage('sprites/effects/scorch3.png')
sprites.effects.triangleScorch = love.graphics.newImage('sprites/effects/scorch/triangle.png')
sprites.effects.darkMagicB = love.graphics.newImage('sprites/effects/darkMagicB.png')
sprites.effects.darkMagicW = love.graphics.newImage('sprites/effects/darkMagicW.png')
sprites.effects.death = love.graphics.newImage('sprites/effects/death.png')
sprites.effects.arrowShadow = love.graphics.newImage('sprites/effects/shadows/arrow.png')
sprites.effects.boomerangShadow = love.graphics.newImage('sprites/effects/shadows/boomerang.png')
sprites.effects.treeShadow = love.graphics.newImage('sprites/effects/shadows/tree.png')
sprites.effects.fireball = love.graphics.newImage('sprites/effects/fireball.png')
-- the magic pack: sheets of 72 x 72 frames, each with its quads (sprites.effects.magicQuads[name])
sprites.effects.magic = {}
sprites.effects.magicQuads = {}
for _, name in ipairs({ "laser", "fireball", "fireballDiagonal", "fireballBurst", "summonCircle", "splash", "smokeBurst", "flame" }) do
    local sheet = love.graphics.newImage('sprites/effects/magic/' .. name .. '.png')
    sprites.effects.magic[name] = sheet
    sprites.effects.magicQuads[name] = {}
    for i = 1, sheet:getWidth() / 72 do
        sprites.effects.magicQuads[name][i] = love.graphics.newQuad((i - 1) * 72, 0, 72, 72, sheet:getDimensions())
    end
end
-- the laser in two layers, so a beam can be drawn in any colour: its whole shape
-- (the orange flecks on its ragged edge included) and just its white-hot core
do
    local shape = love.image.newImageData('sprites/effects/magic/laser.png')
    local core = shape:clone()
    shape:mapPixel(function(_, _, _, _, _, a) return 1, 1, 1, a end)
    core:mapPixel(function(_, _, _, g, _, a)
        if g < 0.9 then return 0, 0, 0, 0 end
        return 1, 1, 1, a
    end)
    sprites.effects.magic.laserShape = love.graphics.newImage(shape)
    sprites.effects.magic.laserCore = love.graphics.newImage(core)
end
sprites.effects.blobs = {}
sprites.effects.blobs.blob1 = love.graphics.newImage('sprites/effects/blobs/blob1.png')
sprites.effects.blobs.blob2 = love.graphics.newImage('sprites/effects/blobs/blob2.png')
sprites.effects.blobs.blob3 = love.graphics.newImage('sprites/effects/blobs/blob3.png')
sprites.effects.blobs.blob4 = love.graphics.newImage('sprites/effects/blobs/blob4.png')
sprites.environment = {}
sprites.environment.breakableRock = love.graphics.newImage('sprites/environment/breakableRock.png')
sprites.environment.breakableWall = love.graphics.newImage('sprites/environment/breakableWall.png')
sprites.environment.lockedDoor = love.graphics.newImage('sprites/environment/lockedDoor.png')
sprites.environment.tree = love.graphics.newImage('sprites/environment/tree.png')
sprites.environment.tree2 = love.graphics.newImage('sprites/environment/tree2.png')
sprites.environment.wave = love.graphics.newImage('sprites/environment/wave.png')
sprites.environment.checkpoint = love.graphics.newImage('sprites/environment/checkpoint.png')
sprites.village = {}
sprites.village.house1 = love.graphics.newImage('sprites/tiny_swords/buildings/house1.png')
sprites.village.house2 = love.graphics.newImage('sprites/tiny_swords/buildings/house2.png')
sprites.village.house3 = love.graphics.newImage('sprites/tiny_swords/buildings/house3.png')
sprites.village.castle = love.graphics.newImage('sprites/tiny_swords/buildings/castle.png')
sprites.village.tower = love.graphics.newImage('sprites/tiny_swords/buildings/tower.png')
sprites.village.bushes1 = love.graphics.newImage('sprites/tiny_swords/terrain/bushes/bush1.png')
sprites.village.bushes2 = love.graphics.newImage('sprites/tiny_swords/terrain/bushes/bush2.png')
sprites.village.trees1 = love.graphics.newImage('sprites/tiny_swords/terrain/trees/tree1.png')
sprites.village.trees2 = love.graphics.newImage('sprites/tiny_swords/terrain/trees/tree2.png')
sprites.village.rock1 = love.graphics.newImage('sprites/tiny_swords/terrain/rocks/rock1.png')
sprites.village.rock2 = love.graphics.newImage('sprites/tiny_swords/terrain/rocks/rock2.png')
sprites.village.rock3 = love.graphics.newImage('sprites/tiny_swords/terrain/rocks/rock3.png')
sprites.village.rock4 = love.graphics.newImage('sprites/tiny_swords/terrain/rocks/rock4.png')
sprites.village.foodCrates = love.graphics.newImage('sprites/village/foodCrates.png')
sprites.village.tiles = love.graphics.newImage('maps/_tilesets/Overworld-comfy.png')
sprites.village.hemiStall = love.graphics.newImage('sprites/village/hemiStall.png')
sprites.village.veStall = love.graphics.newImage('sprites/village/veStall.png')
sprites.veHemi = love.graphics.newImage('sprites/items/veHemi.png')
sprites.village.guildHall = love.graphics.newImage('sprites/village/guildHall.png')
sprites.village.windmill = love.graphics.newImage('sprites/village/windmill.png')
sprites.village.gate = love.graphics.newImage('sprites/village/gate.png')
sprites.village.windmillSails = love.graphics.newImage('sprites/village/windmillSails.png')
sprites.hemi = love.graphics.newImage('sprites/hemi.png')
sprites.enemies = {}
sprites.enemies.alert = love.graphics.newImage('sprites/enemies/alert.png')
sprites.enemies.shadow = love.graphics.newImage('sprites/enemies/shadow.png')
sprites.enemies.shadowMed = love.graphics.newImage('sprites/enemies/shadowMed.png')
sprites.enemies.eye1 = love.graphics.newImage('sprites/enemies/eye/eye1.png')
sprites.enemies.eye2 = love.graphics.newImage('sprites/enemies/eye/eye2.png')
sprites.enemies.eye3 = love.graphics.newImage('sprites/enemies/eye/eye3.png')
sprites.enemies.eyeShadow = love.graphics.newImage('sprites/enemies/eye/eyeShadow.png')
sprites.enemies.eyeDead1 = love.graphics.newImage('sprites/enemies/eye/eyeDead1.png')
sprites.enemies.eyeDead2 = love.graphics.newImage('sprites/enemies/eye/eyeDead2.png')
sprites.enemies.eyeDead3 = love.graphics.newImage('sprites/enemies/eye/eyeDead3.png')
sprites.enemies.eyeBody = love.graphics.newImage('sprites/enemies/eye2/eyeBody.png')
sprites.enemies.iris1 = love.graphics.newImage('sprites/enemies/eye2/iris1.png')
sprites.enemies.bat = love.graphics.newImage('sprites/enemies/bat.png')
sprites.enemies.batDead = love.graphics.newImage('sprites/enemies/batDead.png')
sprites.enemies.skeletonKnife = love.graphics.newImage('sprites/enemies/skeleton/knife2.png')
sprites.enemies.skeletonMage = love.graphics.newImage('sprites/enemies/skeleton/mage.png')
sprites.enemies.skeletonDead = love.graphics.newImage('sprites/enemies/skeleton/skeletonStun.png')
sprites.enemies.rickSheet = love.graphics.newImage('sprites/enemies/rick/rickSheet.png')
sprites.enemies.rickPortrait = love.graphics.newImage('sprites/enemies/rick/rickPortrait.png')
-- the Whispering Woods' slimes (1 blue, 2 yellow, 3 red): a sheet per action,
-- 64 x 64 frames, one row per facing (down, up, left, right)
sprites.enemies.slimes = {}
for n = 1, 3 do
    sprites.enemies.slimes[n] = {}
    for _, action in ipairs({ "Idle", "Walk", "Attack", "Hurt", "Death" }) do
        sprites.enemies.slimes[n][action:lower()] = love.graphics.newImage('sprites/enemies/slime/Slime' .. n .. '_' .. action .. '.png')
    end
end
sprites.enemies.gulaSheet = love.graphics.newImage('sprites/enemies/gula/gulaSheet.png')
sprites.enemies.gulaPortrait = love.graphics.newImage('sprites/enemies/gula/gulaPortrait.png')
sprites.items = {}
sprites.items.sword = love.graphics.newImage('sprites/items/sword.png')
sprites.items.sword2 = love.graphics.newImage('sprites/items/sword2.png')
sprites.items.arrow = love.graphics.newImage('sprites/items/arrow.png')
sprites.items.bow1 = love.graphics.newImage('sprites/items/bow1.png')
sprites.items.bow2 = love.graphics.newImage('sprites/items/bow2.png')
sprites.items.bowIcon = love.graphics.newImage('sprites/items/bowIcon.png')
sprites.items.bomb = love.graphics.newImage('sprites/items/bomb.png')
sprites.items.bombSheet = love.graphics.newImage('sprites/items/bombSheet.png')
sprites.items.boomerang = love.graphics.newImage('sprites/items/boomerang.png')
sprites.items.fire = love.graphics.newImage('sprites/items/fire-icon.png')
sprites.items.grapple = love.graphics.newImage('sprites/items/grapple.png')
sprites.items.grappleArmed = love.graphics.newImage('sprites/items/grapple-armed.png')
sprites.items.grappleChain = love.graphics.newImage('sprites/items/grapple-chain.png')
sprites.items.grappleHandle = love.graphics.newImage('sprites/items/grapple-handle.png')
sprites.items.grappleHead = love.graphics.newImage('sprites/items/grapple-head.png')
sprites.items.key = love.graphics.newImage('sprites/items/key.png')
sprites.items.coin = love.graphics.newImage('sprites/items/coin.png')
sprites.items.coin1 = love.graphics.newImage('sprites/items/coin1Sheet.png')
sprites.items.coin2 = love.graphics.newImage('sprites/items/coin2Sheet.png')
sprites.items.coin3 = love.graphics.newImage('sprites/items/coin3Sheet.png')
sprites.items.heart = love.graphics.newImage('sprites/items/heart.png')
sprites.items.container = love.graphics.newImage('sprites/items/container.png')
sprites.items.quiver = love.graphics.newImage('sprites/items/quiver.png')
sprites.items.lantern = love.graphics.newImage('sprites/items/lantern.png')
sprites.items.lootShadow = love.graphics.newImage('sprites/items/lootShadow.png')
sprites.items.lootShadow2 = love.graphics.newImage('sprites/items/lootShadow2.png')
sprites.items.chestClosed = love.graphics.newImage('sprites/environment/chestClosed.png')
sprites.items.chestOpen = love.graphics.newImage('sprites/environment/chestOpen.png')
sprites.items.chestBigClosed = love.graphics.newImage('sprites/environment/chestBigClosed.png')
sprites.items.chestBigOpen = love.graphics.newImage('sprites/environment/chestBigOpen.png')
sprites.items.food = love.graphics.newImage('sprites/items/food.png')
sprites.items.shadowStep = love.graphics.newImage('sprites/items/shadowStep.png')
sprites.items.staff = love.graphics.newImage('sprites/items/stormStaff.png')
sprites.items.mobLoot = love.graphics.newImage('sprites/items/mobLoot.png')
sprites.hud = {}
sprites.hud.heart = love.graphics.newImage('sprites/ui/heart.png')
sprites.hud.halfHeart = love.graphics.newImage('sprites/ui/heart-half.png')
sprites.hud.emptyHeart = love.graphics.newImage('sprites/ui/heart-empty.png')
sprites.hud.itemBox = love.graphics.newImage('sprites/ui/itemBox.png')
sprites.hud.ammoBox = love.graphics.newImage('sprites/ui/ammoBox.png')
sprites.hud.coin = love.graphics.newImage('sprites/items/coinIcon.png')
-- the health, stamina and mana panel, and the strips that fill its troughs
sprites.hud.panel = love.graphics.newImage('sprites/ui/hud/panel.png')
sprites.hud.fills = {}
for _, kind in ipairs({ "hp", "stamina", "mana" }) do
    sprites.hud.fills[kind] = love.graphics.newImage('sprites/ui/hud/' .. kind .. 'Fill.png')
end
sprites.pause = {}
sprites.pause.equipBox = love.graphics.newImage('sprites/ui/pause/equipBox.png')
sprites.pause.wideBox = love.graphics.newImage('sprites/ui/pause/wideBox.png')
sprites.pause.itemPanel = love.graphics.newImage('sprites/ui/pause/itemPanel.png')
sprites.pause.itemPanelL = love.graphics.newImage('sprites/ui/pause/itemPanelL.png')
sprites.pause.itemPanelR = love.graphics.newImage('sprites/ui/pause/itemPanelR.png')
sprites.pause.itemPanelFade = love.graphics.newImage('sprites/ui/pause/itemPanelFade.png')
sprites.pause.mouse = love.graphics.newImage('sprites/ui/pause/mouse.png')
sprites.pause.cursor = love.graphics.newImage('sprites/ui/pause/cursor.png')
-- the villagers (src/levels/npc.lua): citizens idle and walk four ways, traders stand and work
sprites.npc = {}
for _, look in ipairs({ "citizen1", "citizen2", "citizen3", "citizen4", "citizen5", "juan", "hilda", "tom", "mira" }) do
    sprites.npc[look] = {
        idle = love.graphics.newImage('sprites/npc/citizens/' .. look .. '_idle.png'),
        walk = love.graphics.newImage('sprites/npc/citizens/' .. look .. '_walk.png'),
    }
end
sprites.npc.weaponTrader = love.graphics.newImage('sprites/npc/traders/weapon.png')
sprites.npc.breadTrader = love.graphics.newImage('sprites/npc/traders/bread.png')
sprites.npc.drinksTrader = love.graphics.newImage('sprites/npc/traders/drinks.png')
sprites.npc.witch = love.graphics.newImage('sprites/npc/traders/magic.png')
-- the hero's dialogue portrait: the first frame of the player sheet, so it always matches the player
do
    local sheet = love.image.newImageData('sprites/player/playerSheet.png')
    local frame = love.image.newImageData(19, 21)
    frame:paste(sheet, 0, 0, 0, 0, 19, 21)
    sprites.npc.hero = love.graphics.newImage(frame)
end
sprites.npc.rick = sprites.enemies.rickPortrait

-- quads into the 8x8 food sheet: bread, apple, drumstick, cheese
sprites.items.foodQuads = {}
for i = 1, 4 do
    sprites.items.foodQuads[i] = love.graphics.newQuad((i - 1) * 8, 0, 8, 8, sprites.items.food:getDimensions())
end

-- quads into the food crate sheet: 4 full crates, then the empty one
sprites.village.crateQuads = {}
for i = 1, 5 do
    sprites.village.crateQuads[i] = love.graphics.newQuad((i - 1) * 16, 0, 16, 24, sprites.village.foodCrates:getDimensions())
end

-- quads into the 4 frame Rick sheet: closed, chomp, wide, dizzy
sprites.enemies.rickQuads = {}
for i = 1, 4 do
    sprites.enemies.rickQuads[i] = love.graphics.newQuad((i - 1) * 38, 0, 38, 54, sprites.enemies.rickSheet:getDimensions())
end

-- single tiles from the village tileset (used for fences and barricades)
function getVillageTileQuad(gid)
    sprites.village.tileQuads = sprites.village.tileQuads or {}
    if not sprites.village.tileQuads[gid] then
        local index = gid - 1
        local columns = sprites.village.tiles:getWidth() / 16
        sprites.village.tileQuads[gid] = love.graphics.newQuad((index % columns) * 16, math.floor(index / columns) * 16, 16, 16, sprites.village.tiles:getDimensions())
    end
    return sprites.village.tileQuads[gid]
end

-- since fonts are influenced by scale, they need to be re-initialized when the scale changes
function initFonts()
    fonts = {}
    fonts.debug = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 15*scale)
    fonts.debug2 = love.graphics.newFont(10*scale)
    fonts.debugSmall = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 10*scale)
    fonts.dev = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 14)
    fonts.ammo = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 4.5*scale)
    fonts.coins = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 6.5*scale)
    fonts.shop = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 8)

    fonts.pause1 = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 12*scale)
    fonts.pause2 = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 9*scale)
    fonts.pauseTop = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 10*scale)

    fonts.dialogue = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 8.5*scale)
    fonts.dialogueName = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 7.5*scale)
    fonts.small = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 6.5*scale)
    fonts.hud = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 4*scale)
    fonts.hudSmall = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 2.6*scale)
    fonts.hudGoal = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 5*scale)
    fonts.menu = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 5.5*scale)
    fonts.menuSmall = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 4.5*scale)
    fonts.float = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 3.5*scale)
    fonts.toast = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 9*scale)
    fonts.vs = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 20*scale)
    fonts.vsName = love.graphics.newFont("fonts/kenney-pixel-square/Kenney-Pixel-Square.ttf", 6*scale)
    fonts.vsTitle = love.graphics.newFont("fonts/vt323/VT323-Regular.ttf", 6*scale)
end
initFonts()

sounds = {}
sounds.enemies = {}
sounds.enemies.die = 'sounds/enemies/enemyDie.wav'
sounds.enemies.hurt = 'sounds/enemies/enemyHurt.wav'
sounds.enemies.projectile = 'sounds/enemies/projectile.wav'
sounds.enemies.gulaCharge = 'sounds/enemies/gulaCharge.wav'
sounds.enemies.gulaThunder = 'sounds/enemies/gulaThunder.wav'
sounds.items = {}
sounds.items.arrow = 'sounds/items/arrow.wav'
sounds.items.boomerang = 'sounds/items/boomerang.wav'
sounds.items.chest = 'sounds/items/chest.wav'
sounds.items.coin = 'sounds/items/coin-edit.wav'
sounds.items.explosion = 'sounds/items/explosion.wav'
sounds.items.fire = 'sounds/items/fire.wav'
sounds.items.grapple = 'sounds/items/grapple.wav'
sounds.items.set = 'sounds/items/set.wav'
sounds.items.sword = 'sounds/items/sword.wav'
sounds.player = {}
sounds.player.hurt = 'sounds/player/playerHurt.wav'
sounds.player.roll = 'sounds/player/roll.wav'
sounds.ui = {}
sounds.ui.click = 'sounds/ui/click.wav'
sounds.ui.select = 'sounds/ui/select.wav'
sounds.ui.menuOpen = 'sounds/ui/menu-open.wav'
sounds.ui.menuClose = 'sounds/ui/menu-close.wav'
