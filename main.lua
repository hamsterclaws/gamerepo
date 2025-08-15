-- Love2D Stat-Based Fight Sim (with per-entity image scaling)
-- Uses items.lua and monsters.lua in the project root (require("items"), require("monsters"))

local W, H = 800, 600
local menuHeightFrac = 1/3
local ui = { weaponScroll = 0, armorScroll = 0, logScroll = 0, magicScroll = 0, useMagic = false, selectedSpellIndex = nil }
local fonts = {}

-- ====== Dynamic text fitting helpers ======
local fontCache = {}
local function getFontSized(px)
  if not fontCache[px] then fontCache[px] = love.graphics.newFont(px) end
  return fontCache[px]
end

-- Fit text in a given width (and optional height) by shrinking font size.
-- Returns the font used and the chosen size.
local function fittedText(text, maxW, maxH, startPx, minPx)
  startPx = startPx or 18
  minPx   = minPx   or 10
  local size = startPx
  while size > minPx do
    local f = getFontSized(size)
    local w = f:getWidth(text)
    local h = f:getHeight()
    if w <= maxW and (not maxH or h <= maxH) then
      return f, size
    end
    size = size - 1
  end
  return getFontSized(minPx), minPx
end

-- Draw fitted text at (x,y) within a max box (w,h). Uses printf for clean clipping.
local function drawFittedText(text, x, y, w, h, startPx, minPx, align)
  local f = select(1, fittedText(text, w, h, startPx, minPx))
  love.graphics.setFont(f)
  love.graphics.printf(text, x, y, w, align or "left")
end


-- Inventory list icon size (unchanged; keeps inventory tidy)
local ICON_SIZE = 40

-- === Global defaults (Step 3) ===
-- Applied to the LARGE images shown in the top area (monster and loot popup).
-- You can tweak these to make everything bigger/smaller at once.
local DEFAULT_MONSTER_SCALE = 1.5
local DEFAULT_LOOT_SCALE    = 1.3

local DEFAULT_PLAYER_SCALE = 1.4
local PLAYER_IMAGE = "assets/monsters/player.png"
local PLAYER_FACE_RIGHT = false  -- set to false if your sprite already faces right

local Items = require("items")
local Monsters = require("monsters")
local MagicData = require("magic")


-- ########################
-- ## Game Data & State  ##
-- ########################

-- XP curve: cumulative XP required to *reach* level N (index = level)
local XP_TABLE = { 0, 10, 30, 60, 100, 150, 210, 280 }
local function xpForLevel(level)
  if XP_TABLE[level] then return XP_TABLE[level] end
  local last = XP_TABLE[#XP_TABLE]
  return last + (level - #XP_TABLE) * 70
end

local player = { baseHP = 30, baseATK = 5, baseDEF = 1, hp = 30, level = 1, xp = 0,
                 stats = { STR = 0, VIT = 0, DEF = 0 }, statPoints = 0,
                 weapon = nil, armor  = nil, magic = 0, }
local items  = { weapons = {}, armors = {} }
local monsters = {}
local sprites = { items = {}, monsters = {}, backgrounds = {}, player = nil }

-- === Backgrounds (top 2/3) ===
-- Replace these with your actual PNGs under ./assets/backgrounds/
local BG_LIST = {
  "assets/backgrounds/zone1.png", -- levels   1–10
  "assets/backgrounds/zone2.png", -- levels  11–20
  "assets/backgrounds/zone3.png", -- levels  21–30
  "assets/backgrounds/zone4.png", -- levels  31–40
  "assets/backgrounds/zone5.png", -- levels  41–50
}

local bg = {
  current = nil,      -- Image
  next = nil,         -- Image during transition
  t = 1,              -- 0→1 progress of transition (1 = done)
  duration = 2.0,     -- seconds for a soft cross-fade - og 0.8
  mode = "cover",     -- "cover" | "stretch" | "contain"
}

local game = {
  currentMonster = nil,
  monsterIndex = 0,
  inBattle = false,
  battleTimer = 0,
  -- Player and Monster turn in seconds
  turnInterval = 0.8,
  turn = "player",
  log = {"Welcome! Equip gear then press FIGHT."},
  won = false,
  lost = false,
  justLeveled = false,
}

local lootPopup = { visible = false, item = nil, timer = 0, duration = 0.4 }

-- Smooth HP display (animated)
local smoothHP = { player = 1, monster = 1 }

-- Attack bounce animation
local bounce = {
  player = { y = 0, timer = 0 },
  monster = { y = 0, timer = 0 },
}


-- Works with both code versions: uses totalHP() if present, else baseHP
local function getPlayerMaxHP()
  return (type(totalHP) == "function") and totalHP() or player.baseHP
end


-- Only these are available at start (others must drop)
local START_WEAPONS = { stick=true, sword=false }
local START_ARMORS  = { cloth=true, chain=false }


-- ########################
-- ## Helpers            ##
-- ########################
local function totalATK()
  local statATK = (player.stats and player.stats.STR or 0) * 1
  return player.baseATK + statATK
    + (player.weapon and (player.weapon.atk or 0) or 0)
    + (player.armor  and (player.armor.atk  or 0) or 0)
end

local function totalDEF()
  local statDEF = (player.stats and player.stats.DEF or 0) * 0.5
  return player.baseDEF + statDEF
    + (player.weapon and (player.weapon.def or 0) or 0)
    + (player.armor  and (player.armor.def  or 0) or 0)
end

local function totalMAG()
  return (player.magic or 0)
       + (player.weapon and (player.weapon.magic or 0) or 0)
       + (player.armor  and (player.armor.magic  or 0) or 0)
end


local function totalHP()
  local statHP = (player.stats and player.stats.VIT or 0)
  return player.baseHP + statHP
    -- + (player.weapon and (player.weapon.def or 0) or 0)
    -- + (player.armor  and (player.armor.def  or 0) or 0)
end

local function round(n) return math.floor(n + 0.5) end

local function drawScaledText(text, x, y, maxWidth, baseSize, color)
    local fontSize = baseSize
    local font = love.graphics.newFont(fontSize)

    while font:getWidth(text) > maxWidth and fontSize > 8 do
        fontSize = fontSize - 1
        font = love.graphics.newFont(fontSize)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
end


local function magicDamageAgainst(mon)
  local spell = MagicData[ui.selectedSpellIndex]
  if not spell then return 1 end
  local base = totalMAG() * (spell.power or 1.0)
  local def  = mon.def or 0
  return math.max(1, round(base - def))
end

local function pushLog(text)
  table.insert(game.log, 1, text)
  if #game.log > 100 then table.remove(game.log) end
end

local function resetPlayerHP()
  player.hp = totalHP ()
end


-- Draw an image to the top area, using cover/contain/stretch
local function drawBackgroundImage(img, x, y, w, h, mode)
  if not img then return end
  local iw, ih = img:getDimensions()
  local sx, sy, dx, dy = 1, 1, x, y

  if mode == "cover" then
    local s = math.max(w / iw, h / ih)
    sx, sy = s, s
    dx = x + (w - iw * s) * 0.5
    dy = y + (h - ih * s) * 0.5
  elseif mode == "contain" then
    local s = math.min(w / iw, h / ih)
    sx, sy = s, s
    dx = x + (w - iw * s) * 0.5
    dy = y + (h - ih * s) * 0.5
  elseif mode == "stretch" then
    sx, sy = w / iw, h / ih
    dx, dy = x, y
  end

  --love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, dx, dy, 0, sx, sy)
end

-- Round → zone (1..10 = zone1, 11..20 = zone2, ...)
local function zoneIndexForRound(roundIndex)
  local idx = math.floor((math.max(1, roundIndex) - 1) / 10) + 1
  if idx > #BG_LIST then idx = #BG_LIST end
  return idx
end

local function setBackgroundForRound(roundIndex)
  local idx = zoneIndexForRound(roundIndex)
  local target = sprites.backgrounds[idx]
  if not target then
    pushLog(("No background image for zone %d (round %d)"):format(idx, roundIndex))
    return
  end

  if not bg.current then
    bg.current = target
    bg.next = nil
    bg.t = 1
    pushLog(("Init background -> zone %d"):format(idx))
    return
  end

  if bg.current ~= target then
    bg.next = target
    bg.t = 0
    pushLog(("Switching background -> zone %d (round %d)"):format(idx, roundIndex))
  end
end

-- Add a specific item to runtime inventory if missing
local function addItemIfMissing(kind, id)
  local list = items[kind]
  for _, it in ipairs(list) do if it.id == id then return false end end
  local src = (kind == "weapons") and Items.weapons or Items.armors
  for _, it in ipairs(src) do
    if it.id == id then
      local copy = {}; for k,v in pairs(it) do copy[k]=v end
      table.insert(list, copy)
      if copy.img and not sprites.items[copy.id] then
        local ok, img = pcall(love.graphics.newImage, copy.img)
        if ok then sprites.items[copy.id] = img end
      end
      return true
    end
  end
  return false
end

-- Resolve an item id to either weapons or armors and add it
local function addItemById(id)
  for _, it in ipairs(Items.weapons) do if it.id == id then return addItemIfMissing("weapons", id) end end
  for _, it in ipairs(Items.armors)  do if it.id == id then return addItemIfMissing("armors",  id) end end
  return false
end

-- Loot chance helpers
local function normalizeChance(c)
  if not c then return 100 end
  if c <= 1 then return c * 100 end
  return c
end

local function grantLootForMonster(monDef)
  if not monDef or not monDef.loot then return end
  local gained = {}
  for _, entry in ipairs(monDef.loot) do
    local id, chance
    if type(entry) == "string" then
      id, chance = entry, 100
    elseif type(entry) == "table" then
      id = entry.id
      chance = normalizeChance(entry.chance or entry.dropChance or 100)
    end
    if id then
      local roll = math.random(100)
      pushLog("Rolled "..roll.." for "..id.." (needs ≤ "..chance..")")
      if roll <= chance then
        if addItemById(id) then
          table.insert(gained, id)
          break -- only one drop per monster kill
        end
      end
    end
  end
  if #gained > 0 then
    local gainedId = gained[1]
    pushLog("Loot: " .. gainedId .. " acquired!")
    -- Look up the item object to show in popup
    lootPopup.item = nil
    for _, it in ipairs(Items.weapons) do if it.id == gainedId then lootPopup.item = it end end
    for _, it in ipairs(Items.armors)  do if it.id == gainedId then lootPopup.item = it end end
    if lootPopup.item then
      lootPopup.visible = true
      lootPopup.timer = 0
      game.inBattle = false
    end
  end
end

-- Leveling
local function checkLevelUps()
  while player.xp >= xpForLevel(player.level + 1) do
    player.level = player.level + 1
    player.statPoints = (player.statPoints or 0) + 3
    player.baseHP = player.baseHP + 5
    resetPlayerHP()
    leveled = true
    pushLog(("Level up! Now level %d (+3 stat points, +5 base HP)."):format(player.level))
  end
  if leveled then
    game.justLeveled = true
  end
end


local function awardXPForKill(monDef)
  local gained = (monDef and monDef.xp) or 0
  if gained > 0 and game.justLeveled then
    game.justLeveled = false
  end
  if gained > 0 then
    player.xp = player.xp + gained
    pushLog(("Gained %d XP."):format(gained))
    checkLevelUps()
  end
end


-- Monster flow
local function spawnNextMonster()
  if game.monsterIndex >= #monsters then
    game.won = true
    pushLog("All monsters defeated! You win.")
    return
  end
  game.monsterIndex = game.monsterIndex + 1
  setBackgroundForRound(game.monsterIndex)
  local base = monsters[game.monsterIndex]
  game.currentMonster = {
    name = base.name,
    hp = base.maxhp, maxhp = base.maxhp,
    atk = base.atk,  def = base.def
  }
  game.inBattle = false
  game.turn = "player"
  resetPlayerHP()
  pushLog(("Round %d — A wild %s appears! (HP %d)"):format(game.monsterIndex, game.currentMonster.name, game.currentMonster.hp))
end

local function damage(a,d) return math.max(1, a - d) end

local function startBattle()
  if game.won or game.inBattle then return end
  if not game.currentMonster or game.currentMonster.hp <= 0 then
    spawnNextMonster()
  end
  if not game.currentMonster then return end
  game.inBattle = true
  game.battleTimer = 0
  game.turn = "player"
  pushLog("Battle started vs ".. game.currentMonster.name .."!")
end

-- ########################
-- ## LOVE Callbacks     ##
-- ########################
function love.load()
  love.window.setMode(W, H, {resizable=true, minwidth=1280, minheight=720})
  --love.window.setMode(W, H, {resizable=true, minwidth=640, minheight=480})
  fonts.title = love.graphics.newFont(24)
  fonts.ui    = love.graphics.newFont(16)
  fonts.small = love.graphics.newFont(13)
  math.randomseed(os.time())

  -- Items: only whitelisted starters at boot
  for _, it in ipairs(Items.weapons) do
    if START_WEAPONS[it.id] then
      table.insert(items.weapons, it)
      if it.img then local ok, img = pcall(love.graphics.newImage, it.img); if ok then sprites.items[it.id] = img end end
    end
  end
  for _, it in ipairs(Items.armors) do
    if START_ARMORS[it.id] then
      table.insert(items.armors, it)
      if it.img then local ok, img = pcall(love.graphics.newImage, it.img); if ok then sprites.items[it.id] = img end end
    end
  end

  -- Monsters and their images (indexed by round order)
  for i, m in ipairs(Monsters) do
    monsters[i] = m
    if m.img then
      local ok, img = pcall(love.graphics.newImage, m.img)
      sprites.monsters[i] = ok and img or nil
    end
  end
  
  -- Player sprite
do
  local ok, img = pcall(love.graphics.newImage, PLAYER_IMAGE)
  if ok then sprites.player = img end
end

  -- Backgrounds
  for i, path in ipairs(BG_LIST) do
    local ok, img = pcall(love.graphics.newImage, path)
    if ok then
      sprites.backgrounds[i] = img
      pushLog(("BG %d ready: %s"):format(i, path))
    else
      pushLog(("BG %d FAILED to load: %s"):format(i, path))
    end
  end

  -- set initial background based on Round 1
  setBackgroundForRound(1)

  
  local ok, img = pcall(love.graphics.newImage, "assets/monsters/player.png")
  if ok then sprites.player = img end

end

function love.resize(nw, nh) W, H = nw, nh end

function love.update(dt)
  if game.inBattle and game.currentMonster and not game.won and not game.lost then
    game.battleTimer = game.battleTimer + dt
    if game.battleTimer >= game.turnInterval then
      game.battleTimer = 0
      if game.turn == "player" then
        local dmg
          if ui.useMagic then
            dmg = magicDamageAgainst(game.currentMonster)
            bounce.player.timer = 0.2  -- same bounce for spells
            local s = MagicData[ui.selectedSpellIndex]
            pushLog(("[Magic] %s for %d!"):format((s and s.name) or "Spell", dmg))
          else
            dmg = damage(totalATK(), game.currentMonster.def)
            bounce.player.timer = 0.2
            pushLog(("You hit %s for %d!"):format(game.currentMonster.name, dmg))
          end
          game.currentMonster.hp = math.max(0, game.currentMonster.hp - dmg)
        if game.currentMonster.hp <= 0 then
          pushLog(game.currentMonster.name .. " is defeated!")
          game.inBattle = false
          awardXPForKill(monsters[game.monsterIndex])
          grantLootForMonster(monsters[game.monsterIndex])
          if game.monsterIndex == #monsters then
            game.won = true
            pushLog("All monsters defeated! You win.")
          end
          if lootPopup.visible then
            lootPopup.timer = lootPopup.timer + dt
          end
        else
          game.turn = "monster"
        end
      else
        local dmg = damage(game.currentMonster.atk, totalDEF())
        player.hp = math.max(0, player.hp - dmg)
        bounce.monster.timer = 0.2  -- short bounce duration
        pushLog(("%s hits you for %d!"):format(game.currentMonster.name, dmg))
        if player.hp <= 0 then
          game.lost = true
          game.inBattle = false
          game.monsterIndex = 0
          game.currentMonster = nil
          pushLog("You were defeated. Progress reset to Round 1. Equip better gear and retry.")
        else
          game.turn = "player"
        end
      end
    end
  end
  -- Smoothly approach target HP percentages
  do
    local targetPlayer = player and getPlayerMaxHP() > 0 and (player.hp / getPlayerMaxHP()) or 0
    local targetMonster = (game.currentMonster and game.currentMonster.maxhp and game.currentMonster.maxhp > 0)
                          and (game.currentMonster.hp / game.currentMonster.maxhp) or 0

    local speed = 6      -- higher = snappier; try 4–10
    local k = math.min(1, speed * dt)

    smoothHP.player  = smoothHP.player  + (targetPlayer  - smoothHP.player)  * k
    smoothHP.monster = smoothHP.monster + (targetMonster - smoothHP.monster) * k
  end
  
  -- Update bounce animations
  for side, b in pairs(bounce) do
    if b.timer > 0 then
      b.timer = b.timer - dt
      local t = math.max(b.timer, 0) / 0.2  -- normalized 0..1
      b.y = math.sin(t * math.pi) * -30      -- up to -10px jump
    else
      b.y = 0
    end
  end

  -- Background cross-fade
  if bg.t < 1 and bg.next then
    bg.t = math.min(1, bg.t + dt / bg.duration)
    if bg.t >= 1 then
      bg.current = bg.next
      bg.next = nil
    end
  end

end

-- Returns a table with all key positions/sizes for the bottom menu layout.
local function menuLayout()
  local menuY   = H * (1 - menuHeightFrac)
  local padding = 12

  -- Left 2/3 area (three columns inside)
  local leftX = padding
  local leftW = math.floor(W * (2/3)) - padding * 2      -- keep left/right gutters

  local gap   = padding
  local colW  = (leftW - gap * 2) / 3                    -- three cols inside left area

  local xWeapons = leftX
  local xArmor   = leftX + colW + gap
  local xMagic   = leftX + (colW + gap) * 2

  -- Right 1/3 area (fight + log)
  local rightX = leftX + leftW + padding
  local rightW = W - rightX - padding

  return {
    menuY = menuY, padding = padding,
    leftX = leftX, leftW = leftW, gap = gap, colW = colW,
    xWeapons = xWeapons, xArmor = xArmor, xMagic = xMagic,
    rightX = rightX, rightW = rightW,
  }
end


-- ########################
-- ## UI Drawing         ##
-- ########################



local function drawBar(x, y, w, h, ratio)
    ratio = math.max(0, math.min(1, ratio)) -- clamp

    local r, g, b
    if ratio > 0.5 then
        local t = (ratio - 0.5) / 0.5 -- 0 at 50%, 1 at 100%
        r, g, b = 1 - t, 1, 0        -- green at 100% → yellow at 50%
    else
        local t = ratio / 0.5        -- 0 at 0%, 1 at 50%
        r, g, b = 1, t, 0            -- red at 0% → yellow at 50%
    end

    -- Border
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", x, y, w, h)

    -- Fill
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", x + 2, y + 2, (w - 4) * ratio, h - 4)

    love.graphics.setColor(1, 1, 1) -- reset
end


local function drawStats()
  love.graphics.setFont(fonts.ui)
  local y = 10
  love.graphics.print("Player", 16, y); y = y + 22
  love.graphics.print(("HP: %d/%d"):format(player.hp, totalHP()), 16, y); y = y + 18
  love.graphics.print(("ATK: %d"):format(totalATK()), 16, y); y = y + 18
  love.graphics.print(("DEF: %d"):format(totalDEF()), 16, y); y = y + 18
  love.graphics.print(("MAG: %d"):format(totalMAG()), 16, y); y = y + 18
  --love.graphics.print(("LVL: %d  XP: %d / %d"):format(player.level, player.xp, xpForLevel(player.level + 1)), 16, y); y = y + 18
  -- XP view: show 0 progress right after level-up
  local floorXP = xpForLevel(player.level)
  local nextXP  = xpForLevel(player.level + 1)
  local need    = nextXP - floorXP
  local have    = game.justLeveled and 0 or math.max(0, player.xp - floorXP)
  love.graphics.print(("LVL: %d  XP: %d / %d"):format(player.level, have, need), 16, y); y = y + 18


  -- Weapon
  local weaponText = "Weapon: " .. (player.weapon and player.weapon.name or "None")
  drawScaledText(weaponText, 16, y, 200, 16, (player.weapon and not ui.useMagic) and {1,1,0,1} or {1,1,1,1})
  y = y + 18

  -- Armor
  local armorText = "Armor:  " .. (player.armor and player.armor.name or "None")
  drawScaledText(armorText, 16, y, 200, 16, player.armor and {1,1,0,1} or {1,1,1,1})
  y = y + 18





  return y
end

local function drawRoundBanner()
  local roundShown = (game.monsterIndex == 0) and 1 or game.monsterIndex
  love.graphics.setFont(fonts.title)
  love.graphics.printf(("Round %d / %d"):format(roundShown, #monsters), 0, 4, W, "center")
end

-- Top-area images: loot (center) OR player (left) vs monster (right)
local function drawArenaImage()
  local topH = H * (1 - menuHeightFrac)
  local arenaY = topH/2 + 20

  -- === 1) Loot popup takes priority (centered, clamped to top 2/3) ===
  if lootPopup.visible and lootPopup.item then
    -- Compute available area (top panel only)
    local topH = H * (1 - menuHeightFrac)

    -- Clip everything we draw for the popup to the top area (safety)
    love.graphics.setScissor(0, 0, W, math.floor(topH))

    local img  = sprites.items[lootPopup.item.id]
    local name = "You received: " .. lootPopup.item.name
    local wantScale = (lootPopup.item.scale or 1) * DEFAULT_LOOT_SCALE

    -- Spacing & metrics
    local padding  = 16
    local gapImgToName = 10
    local gapNameToBtn = 14
    local btnW, btnH = 120, 34

    -- Measure name height
    love.graphics.setFont(fonts.ui)
    local nameH = fonts.ui:getHeight()

    -- Figure out how tall the image may be so that (image + gaps + name + gaps + button) fits in topH
    local chromeH = padding + gapImgToName + nameH + gapNameToBtn + btnH + padding
    local maxImageH = math.max(40, topH - chromeH)  -- leave at least a bit for the image

    -- If we have an image, scale it to fit both width and the computed max height
    local drawX, drawY, finalScale, imgW, imgH = W/2, padding, 1, 0, 0
    if img then
      local iw, ih = img:getDimensions()
      imgW, imgH = iw, ih
      -- Allow the image to be wide; clamp its height to maxImageH and its width to W * 0.6
      local fitScale = math.min(maxImageH / ih, (W * 0.6) / iw)
      finalScale = math.min(wantScale, fitScale)
      local drawW = iw * finalScale
      local drawH = ih * finalScale

      -- Center horizontally; stack from a computed top so the whole block is vertically centered
      local contentH = drawH + gapImgToName + nameH + gapNameToBtn + btnH
      local topY = math.floor((topH - contentH) * 0.5)
      local imgX = math.floor(W/2 - drawW/2)
      local imgY = topY

      love.graphics.setColor(1,1,1)
      love.graphics.draw(img, imgX, imgY, 0, finalScale, finalScale)

      -- Name (centered under image)
      local nameY = imgY + drawH + gapImgToName
      love.graphics.setColor(1,1,1)
      love.graphics.printf(name, 0, nameY, W, "center")

      -- OK button under the name (still inside topH)
      local btnY = nameY + nameH + gapNameToBtn
      lootPopup.okButton = { x = math.floor(W/2 - btnW/2), y = btnY, w = btnW, h = btnH }
      love.graphics.setColor(0.2,0.2,0.2)
      love.graphics.rectangle("fill", lootPopup.okButton.x, lootPopup.okButton.y, btnW, btnH, 6, 6)
      love.graphics.setColor(1,1,1)
      love.graphics.printf("OK", lootPopup.okButton.x, lootPopup.okButton.y + (btnH-16)/2, btnW, "center")
    else
      -- Fallback: simple framed box when the image wasn't found, also clamped to top 2/3
      local boxW, boxH = math.min(420, W - padding*2), math.min(280, topH - padding*2)
      local topY = math.floor((topH - (boxH + gapImgToName + nameH + gapNameToBtn + btnH)) * 0.5)
      local boxX = math.floor(W/2 - boxW/2)
      local boxY = topY

      love.graphics.setColor(1,1,1)
      love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 8, 8)

      local nameY = boxY + boxH + gapImgToName
      love.graphics.printf(name, 0, nameY, W, "center")

      local btnY = nameY + nameH + gapNameToBtn
      lootPopup.okButton = { x = math.floor(W/2 - btnW/2), y = btnY, w = btnW, h = btnH }
      love.graphics.setColor(0.2,0.2,0.2)
      love.graphics.rectangle("fill", lootPopup.okButton.x, lootPopup.okButton.y, btnW, btnH, 6, 6)
      love.graphics.setColor(1,1,1)
      love.graphics.printf("OK", lootPopup.okButton.x, lootPopup.okButton.y + (btnH-16)/2, btnW, "center")
    end

    love.graphics.setScissor() -- clear clipping
    return
  end


  -- === 2) Otherwise: Player (left) vs Monster (right) ===
  if not game.currentMonster then return end

  -- boxes for each side
  local boxW, boxH = 420, 300
  local gap = 60
  local leftCx  = W/2 - gap/2 - boxW/2   -- center-x of left box
  local rightCx = W/2 + gap/2 + boxW/2   -- center-x of right box
  local cy = arenaY

  -- player image (you said it's "assets/monsters/player.png" and already loaded)
  local playerImg = sprites.player or sprites.monsters.player -- try either key, just in case
  local PLAYER_SCALE = 1.3  -- tweak if you want the player bigger/smaller by default

  local function drawFitted(img, cx, cy, wantScale, maxW, maxH, yOffset)
  if not img then return end
  yOffset = yOffset or 0
  local iw, ih = img:getDimensions()
  local fitScale = math.min(maxW / iw, maxH / ih)
  local finalScale = math.min(wantScale, fitScale)
  local drawX = cx - (iw * finalScale) / 2
  local drawY = cy - (ih * finalScale) / 2 + yOffset
  love.graphics.setColor(1,1,1)
  love.graphics.draw(img, drawX, drawY, 0, finalScale, finalScale)
  end

  -- draw player (left)
  if playerImg then
    drawFitted(playerImg, leftCx,  cy, PLAYER_SCALE, boxW, boxH, bounce.player.y)
  end

  -- draw monster (right) with your existing per-monster scale
  local monImg = sprites.monsters[game.monsterIndex]
  local monDef = monsters[game.monsterIndex]
  local monScale = ((monDef and monDef.scale) or 1) * DEFAULT_MONSTER_SCALE
  if monImg then
    drawFitted(monImg,   rightCx,  cy, monScale,     boxW, boxH, bounce.monster.y)
  end

  -- label (keep your existing centered monster name)
  love.graphics.setFont(fonts.ui)
  love.graphics.setColor(1,1,1)
  love.graphics.printf(game.currentMonster.name, 0, cy + boxH/2 + 10, W, "center")
end


-- In drawLog
local function drawLog(x, y, w, h)
  love.graphics.setFont(fonts.small)
  love.graphics.print("Log:", x, y)

  local lineH = 16
  local visible = math.floor((h - 24) / lineH)
  local maxScroll = math.max(0, #game.log - visible)
  ui.logScroll = math.min(maxScroll, math.max(0, ui.logScroll or 0))

  local scroll = ui.logScroll
  local start = math.max(1, scroll + 1)
  local finish = math.min(#game.log, start + visible - 1)

  local textAreaW = w - 20
  local yy = y + 18

  for i = start, finish do
    love.graphics.printf(game.log[i], x, yy + (i-start)*lineH, textAreaW)
  end

  -- Simple scrollbar widgets
  local barX = x + textAreaW + 4
  local barY = y + 18
  local barH = h - 24
  local arrowH = 16
  local trackY = barY + arrowH
  local trackH = barH - arrowH * 2

  ui.logScrollUp   = {x = barX, y = barY,               w = 16, h = arrowH}
  ui.logScrollDown = {x = barX, y = barY + barH - arrowH, w = 16, h = arrowH}

  love.graphics.rectangle("line", ui.logScrollUp.x, ui.logScrollUp.y, ui.logScrollUp.w, ui.logScrollUp.h)
  love.graphics.printf("^", ui.logScrollUp.x, ui.logScrollUp.y, ui.logScrollUp.w, "center")
  love.graphics.rectangle("line", ui.logScrollDown.x, ui.logScrollDown.y, ui.logScrollDown.w, ui.logScrollDown.h)
  love.graphics.printf("v", ui.logScrollDown.x, ui.logScrollDown.y, ui.logScrollDown.w, "center")

  love.graphics.rectangle("line", barX, trackY, 16, trackH)
  if maxScroll > 0 then
    local thumbH = math.max(10, trackH * (visible / #game.log))
    local thumbY = trackY + (trackH - thumbH) * (scroll / maxScroll)
    love.graphics.rectangle("fill", barX + 1, thumbY, 14, thumbH)
  end
end

local function drawStatSpendPanel()
  local topH = H * (1 - menuHeightFrac)
  local panelW, panelH = 220, 120   -- ↑ give the panel a bit more height
  local x, y = 16, topH - panelH - 10

  love.graphics.setFont(fonts.ui)
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("line", x, y, panelW, panelH, 8, 8)

  local title = "Stats"
  if (player.statPoints or 0) > 0 then
    title = title .. "  (+)"
  end
  love.graphics.print(title, x + 8, y + 6)

  -- Lines
  local lineY = y + 30
  local lineH = 22

  ui.statButtons = {}
  local canSpend = (player.statPoints or 0) > 0 and not game.inBattle and not lootPopup.visible

  local function row(label, key, value, rowIndex)
    local ry = lineY + (rowIndex-1) * lineH
    love.graphics.print(("%s: %d"):format(label, value or 0), x + 8, ry)
    if canSpend then
      local bx, by, bw, bh = x + panelW - 34, ry - 2, 26, 20
      love.graphics.rectangle("line", bx, by, bw, bh, 4, 4)
      love.graphics.printf("+", bx, by + 2, bw, "center")
      ui.statButtons[key] = { x = bx, y = by, w = bw, h = bh, stat = key }
    end
  end

  row("STR", "STR", player.stats.STR or 0, 1)
  row("VIT", "VIT", player.stats.VIT or 0, 2)
  row("DEF", "DEF", player.stats.DEF or 0, 3)

  -- Footer: place under the last row with extra padding
  local afterRowsY = lineY + 3 * lineH       -- baseline of last row area
  local footerY    = afterRowsY + 5          -- ↑ 10px gap above "Unspent"
  love.graphics.setFont(fonts.small)
  love.graphics.print(("Unspent points: %d"):format(player.statPoints or 0), x + 8, footerY)
end



local function drawInventoryColumn(kind, x, menuY, colW, padding)
  local header = (kind == "weapons") and "Weapons" or "Armor"
  --simulate below line for different font changes
  love.graphics.setFont(love.graphics.newFont(20))--was 30
  love.graphics.print(header, x, menuY + padding)

  local list = items[kind]
  local itemH = 60
  local topY = menuY + padding + 35
  local listH = (H - menuY) - padding - 8
  local maxVisible = math.max(1, math.floor((listH - 24) / itemH))

  local scrollKey = (kind == "weapons") and "weaponScroll" or "armorScroll"
  local scroll = ui[scrollKey] or 0
  local maxScroll = math.max(0, #list - maxVisible)
  if scroll > maxScroll then scroll = maxScroll end
  if scroll < 0 then scroll = 0 end
  ui[scrollKey] = scroll

  local startIdx = 1 + scroll
  local endIdx = math.min(#list, scroll + maxVisible)

  local buttonsKey = (kind == "weapons") and "weaponButtons" or "armorButtons"
  ui[buttonsKey] = {}

  for i = startIdx, endIdx do
    local it = list[i]
    local row = i - startIdx
    local by = topY + row * itemH
    local r = {x=x, y=by, w=colW, h=itemH-6, item=it, kind=(kind == "weapons") and "weapon" or "armor"}
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)

    -- Keep inventory icons neatly bounded by ICON_SIZE (unchanged)
    local icon = sprites.items[it.id]
    if icon then
      local iw, ih = icon:getDimensions()
      local scaleToFit = math.min(ICON_SIZE/iw, ICON_SIZE/ih)
      love.graphics.draw(icon, r.x + 6, r.y + (itemH-ICON_SIZE)/2, 0, scaleToFit, scaleToFit)
    end

    -- highlight logic with NO dependency on battle/turn
    local isEquippedWeapon = (r.kind == "weapon" and player.weapon and player.weapon.id == it.id)
    local isEquippedArmor  = (r.kind == "armor"  and player.armor  and player.armor.id  == it.id)

    -- show highlight/tag for armor always; for weapons only when Magic is OFF
    local showHighlight = isEquippedArmor or (isEquippedWeapon and not ui.useMagic)
    if showHighlight then
      love.graphics.setColor(1, 1, 0, 0.15)              -- translucent yellow bg
      love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
    end

    -- NEW: dynamic fit inside the row box (single draw only)
    local leftPad   = 6 + ICON_SIZE + 8
    local innerX    = r.x + leftPad
    local innerY    = r.y + 8
    local innerW    = r.w - leftPad - 8     -- right padding
    local innerH    = r.h - 16              -- vertical breathing room

    local label = it.name .. " (".. (it.desc or "") ..")" .. (showHighlight and " [E]" or "")

    -- set text color once (yellow when equipped/highlighted, else white)
    love.graphics.setColor(showHighlight and 1 or 1, showHighlight and 1 or 1, showHighlight and 0 or 1, 1)

    -- single render; no shadow, no second pass
    drawFittedText(label, innerX, innerY, innerW, innerH, 18, 10, "left")

    -- reset color
    love.graphics.setColor(1,1,1,1)



--    local tx, ty = r.x + 6 + ICON_SIZE + 8, r.y + 10
--    if showHighlight then
--      love.graphics.setColor(0, 0, 0, 1)                 -- shadow
--      love.graphics.print(label, tx + 1, ty + 1)
--      love.graphics.setColor(1, 1, 0, 1)                 -- bright yellow
--      love.graphics.print(label, tx, ty)
--    else
--      love.graphics.setColor(1, 1, 1, 1)                 -- normal white
--      love.graphics.print(label, tx, ty)
--    end

--    love.graphics.setColor(1, 1, 1, 1)   

    if equipped then
        love.graphics.setColor(1,1,0)
    end

--    local label = it.name .. " (".. (it.desc or "") ..")" .. (equipped and " [E]" or "")
--    love.graphics.print(label, r.x + 6 + ICON_SIZE + 8, r.y + 10)
--    love.graphics.setColor(1,1,1)

    table.insert(ui[buttonsKey], r)
  end

  if #list > maxVisible then
    love.graphics.setFont(fonts.small)
    love.graphics.printf("Mouse wheel to scroll", x, topY + maxVisible*itemH + 4, colW, "center")
  end
end

local function drawMagicPanel(x, menuY, colW, padding)
  local y = menuY + padding
  love.graphics.setFont(fonts.ui)
  love.graphics.print("Magic", x, y)
  y = y + 24

  -- Toggle (highlight when ON, normal when OFF)
  ui.magicToggle = { x=x, y=y, w=colW, h=26 }

  if ui.useMagic then
    -- translucent yellow fill like equipped items
    love.graphics.setColor(1, 1, 0, 0.15)
    love.graphics.rectangle("fill", ui.magicToggle.x, ui.magicToggle.y, colW, 26, 8, 8)
    love.graphics.setColor(1, 1, 0, 1)  -- yellow outline/text
  else
    love.graphics.setColor(1, 1, 1, 1)  -- white outline/text
  end

  -- outline
  love.graphics.rectangle("line", ui.magicToggle.x, ui.magicToggle.y, colW, 26, 8, 8)

  -- label
  love.graphics.setColor(ui.useMagic and 1 or 1, ui.useMagic and 1 or 1, ui.useMagic and 0 or 1, 1)
  love.graphics.printf(ui.useMagic and "Use Magic: ON" or "Use Magic: OFF", x, y + 6, colW, "center")

  -- reset and advance
  love.graphics.setColor(1, 1, 1, 1)
  y = y + 26 + 6


  -- Spell list
  local listH = 128
  love.graphics.rectangle("line", x, y, colW, listH, 8, 8)

  local lineH = 18
  local maxVisible = math.max(1, math.floor((listH - 8) / lineH))
  local maxScroll = math.max(0, #MagicData - maxVisible)
  ui.magicScroll = math.max(0, math.min(ui.magicScroll or 0, maxScroll))

  local start = 1 + ui.magicScroll
  local finish = math.min(#MagicData, start + maxVisible - 1)

  ui.magicButtons = {}
  for i = start, finish do
    local rowY = y + 4 + (i - start) * lineH
    local selected = ui.useMagic and (i == ui.selectedSpellIndex)

    if selected then love.graphics.setColor(1,1,0) end
    love.graphics.print((selected and "➤ " or "  ") .. MagicData[i].name, x + 6, rowY)
    love.graphics.setColor(1,1,1)
    
    table.insert(ui.magicButtons, { x=x, y=rowY-2, w=colW, h=lineH, index=i })
  end


  love.graphics.setFont(fonts.small)
  love.graphics.printf("Click spell • Wheel to scroll", x, y + listH + 2, colW, "center")
  return y + listH + 22
end


local function drawMenu()
  local L = menuLayout()
  love.graphics.setFont(fonts.ui)

  -- Frame for the whole bottom third
  love.graphics.rectangle("line", 0, L.menuY, W, H - L.menuY)

  -- LEFT 2/3 — three columns
  drawInventoryColumn("weapons", L.xWeapons, L.menuY, L.colW, L.padding)
  drawInventoryColumn("armors",  L.xArmor,   L.menuY, L.colW, L.padding)
  drawMagicPanel(                    L.xMagic,   L.menuY, L.colW, L.padding)

  -- RIGHT 1/3 — Fight button on top
  ui.fightButton = {
    x = L.rightX,
    y = L.menuY + L.padding,
    w = L.rightW,
    h = 44
  }
  love.graphics.rectangle("line", ui.fightButton.x, ui.fightButton.y, ui.fightButton.w, ui.fightButton.h, 10, 10)

  local fbLabel
  if game.won then
    fbLabel = "All Cleared"
  elseif game.lost then
    fbLabel = "Retry from Round 1"
  elseif game.inBattle then
    fbLabel = "Battling..."
  else
    local nextRound = (game.monsterIndex == 0) and 1 or (game.monsterIndex + (game.currentMonster and 0 or 1))
    fbLabel = ("Fight: Round " .. tostring(nextRound))
  end
  love.graphics.printf(fbLabel, ui.fightButton.x, ui.fightButton.y + 12, ui.fightButton.w, "center")

  -- Log fills the rest of the right column
  local logY = ui.fightButton.y + ui.fightButton.h + 8
  local logH = (H - L.menuY) - (logY - L.menuY) - L.padding
  if logH > 40 then
    love.graphics.rectangle("line", L.rightX, logY, L.rightW, logH, 8, 8)
    drawLog(L.rightX + 8, logY + 8, L.rightW - 16, logH - 16)
  end
end


function love.draw()
  love.graphics.clear(0.11,0.12,0.14)


  -- === BACKGROUND (top area only, behind everything) ===
  do
    local topH = H * (1 - menuHeightFrac)
    love.graphics.setScissor(0, 0, W, math.floor(topH))
    love.graphics.setBlendMode("alpha") -- ensure normal alpha blending

    if bg.current and not bg.next then
      -- no transition in progress
      love.graphics.setColor(1, 1, 1, 1)
      drawBackgroundImage(bg.current, 0, 0, W, topH, bg.mode)
    elseif bg.current and bg.next then
      -- cross-fade BOTH layers
      love.graphics.setColor(1, 1, 1, 1 - bg.t)
      drawBackgroundImage(bg.current, 0, 0, W, topH, bg.mode)
      love.graphics.setColor(1, 1, 1, bg.t)
      drawBackgroundImage(bg.next,    0, 0, W, topH, bg.mode)
      love.graphics.setColor(1, 1, 1, 1)
    end

    love.graphics.setScissor()
  end



  

  drawRoundBanner()
  local statsBottom = drawStats()
  drawArenaImage()

  local barW = 220
  local playerBarY = statsBottom + 8
  drawBar(16, playerBarY, barW, 18, smoothHP.player)
  love.graphics.print("Player HP", 16, playerBarY + 22)
  if game.currentMonster then
    drawBar(W - barW - 16, playerBarY, barW, 18, smoothHP.monster)
    love.graphics.print("Monster HP", W - barW - 16, playerBarY + 22)
  end
  
  -- NEW: stat point panel (bottom-left of the top two-thirds)
  drawStatSpendPanel()

  drawMenu()

  love.graphics.setFont(fonts.small)
  love.graphics.printf("Stat Fighter (prototype) — equip gear then FIGHT.", 0, H - 18, W, "center")
end

-- ########################
-- ## Input              ##
-- ########################
local function pointInRect(px, py, r)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function love.mousepressed(x, y, button)
  -- If loot is shown, only allow clicking OK
  if lootPopup.visible then
    if lootPopup.okButton and pointInRect(x, y, lootPopup.okButton) then
      lootPopup.visible = false
      lootPopup.item = nil
    end
    return
  end

  if button ~= 1 then return end
  if game.inBattle then return end
  
    -- Spend stat points with [+] buttons
  if ui.statButtons and (player.statPoints or 0) > 0 and not game.inBattle then
    for _, b in pairs(ui.statButtons) do
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        local k = b.stat
        player.stats[k] = (player.stats[k] or 0) + 1
        player.statPoints = (player.statPoints or 0) - 1

        -- If VIT increases, you might want to keep current HP as-is but ensure it doesn't exceed new max:
        player.hp = math.min(player.hp, totalHP())

        pushLog(("Allocated +1 %s (remaining %d)"):format(k, player.statPoints))
        return
      end
    end
  end

  if ui.weaponButtons then
    for _, r in ipairs(ui.weaponButtons) do
      if pointInRect(x, y, r) then
        if ui.useMagic then
        pushLog("Disable Magic to equip a weapon.")
        return
      end
        if player.weapon and player.weapon.id == r.item.id then
          player.weapon = nil
          pushLog("Unequipped weapon.")
        else
          player.weapon = r.item
          pushLog("Equipped weapon: "..r.item.name)
        end
        return
      end
    end
  end

  if ui.armorButtons then
    for _, r in ipairs(ui.armorButtons) do
      if pointInRect(x, y, r) then
        if player.armor and player.armor.id == r.item.id then
          player.armor = nil
          pushLog("Unequipped armor.")
        else
          player.armor = r.item
          pushLog("Equipped armor: "..r.item.name)
        end
        return
      end
    end
  end
  -- Magic toggle (mutually exclusive with weapons)
  if ui.magicToggle and pointInRect(x, y, ui.magicToggle) then
    ui.useMagic = not ui.useMagic
    if ui.useMagic then
      -- turning magic ON clears any equipped weapon
      if player.weapon then
        player.weapon = nil
      end
      pushLog("Magic enabled. Weapon deselected.")
    else
      -- turning magic OFF keeps the weapon deselected (do nothing)
      pushLog("Magic disabled.")
    end
    return
  end


  -- Select spell
  if ui.magicButtons then
    for _, r in ipairs(ui.magicButtons) do
      if pointInRect(x, y, r) then
        ui.selectedSpellIndex = r.index
        local s = MagicData[ui.selectedSpellIndex]
        pushLog("Selected spell: " .. (s and s.name or "Unknown"))
        return
      end
    end
  end


  if ui.fightButton and pointInRect(x, y, ui.fightButton) then
    if game.won then return end
    if game.lost then
      game.lost = false
      game.monsterIndex = 0
      game.currentMonster = nil
      pushLog("Retrying from Round 1.")
    end
    startBattle()
  end
end

function love.wheelmoved(dx, dy)
  if dy == 0 then return end

  local mx, my = love.mouse.getPosition()
  local L = menuLayout()

  local function inArea(a)
    return mx >= a.x and mx <= a.x + a.w and my >= a.y and my <= a.y + a.h
  end

  -- List rectangles for the three left columns
  local listAreaWeapons = { x = L.xWeapons, y = L.menuY + L.padding, w = L.colW, h = H - L.menuY - L.padding }
  local listAreaArmors  = { x = L.xArmor,   y = L.menuY + L.padding, w = L.colW, h = H - L.menuY - L.padding }
  local listAreaMagic   = { x = L.xMagic,   y = L.menuY + L.padding, w = L.colW, h = H - L.menuY - L.padding }

  if inArea(listAreaWeapons) then
    ui.weaponScroll = math.max(0, (ui.weaponScroll or 0) - dy)
    return
  end
  if inArea(listAreaArmors) then
    ui.armorScroll  = math.max(0, (ui.armorScroll  or 0) - dy)
    return
  end
  if inArea(listAreaMagic) then
    ui.magicScroll  = math.max(0, (ui.magicScroll  or 0) - dy)
    return
  end

  -- Right column (log) wheel support
  local fightH = 44
  local logY   = L.menuY + L.padding + fightH + 8
  local logH   = H - logY - L.padding
  local inLogArea = mx >= L.rightX and mx <= L.rightX + L.rightW and my >= logY and my <= logY + logH
  if inLogArea then
    local lineH   = 16
    local visible = math.floor((logH - 24) / lineH)
    local maxScroll = math.max(0, #game.log - visible)
    ui.logScroll = math.max(0, math.min(maxScroll, (ui.logScroll or 0) - dy))
  end
end


function love.keypressed(key)
  if key == "return" or key == "space" then
    if not game.inBattle then startBattle() end
  elseif key == "r" then
    game = {
      currentMonster=nil, monsterIndex=0, inBattle=false, battleTimer=0,
      turnInterval=0.45, turn="player", log={"Reset. Equip gear then press FIGHT."},
      won=false, lost=false
    }
    resetPlayerHP()
    setBackgroundForRound(1)
    player.weapon = nil
    player.armor = nil
  end
end
