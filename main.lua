-- main.lua — Love2D Stat-Based Fight Sim (full version)
-- Uses items.lua and monsters.lua in the project root (require("items"), require("monsters"))
-- Features:
--  • Top 2/3 battle scene, bottom 1/3 inventory + Fight + log
--  • Round banner (shows Round 1 before first fight)
--  • Click to equip/unequip; equipped items highlighted yellow
--  • Auto-resolve, turn-based fights; reset to Round 1 on death
--  • Scrollable inventories with mouse wheel
--  • Item icons scaled to ICON_SIZE inside rows
--  • Starter item whitelist (Option B) so loot-only items don't appear at start
--  • Monster-specific loot in monsters.lua with percentage drop rates (0–100 or 0.0–1.0)

local W, H = 800, 600
local menuHeightFrac = 1/3
local ui = { weaponScroll = 0, armorScroll = 0, logScroll = 0 }
local fonts = {}
local ICON_SIZE = 28 -- scaled icon size for inventory items

local Items = require("items")
local Monsters = require("monsters")

-- ########################
-- ## Game Data & State  ##
-- ########################
local player = { baseHP = 30, baseATK = 5, baseDEF = 1, hp = 30, weapon = nil, armor  = nil }
local items  = { weapons = {}, armors = {} }
local monsters = {}
local sprites = { items = {}, monsters = {} }

local game = {
  currentMonster = nil,
  monsterIndex = 0,  -- 0 = none spawned yet (banner shows Round 1)
  inBattle = false,
  battleTimer = 0,
  turnInterval = 0.45,
  turn = "player",
  log = {"Welcome! Equip gear then press FIGHT."},
  won = false,
  lost = false,
}
local lootPopup = {
  visible = false,
  item = nil,
  timer = 0,
  duration = 0.4,  -- animation time (in seconds)
}
-- Only these are available at start (others must drop)
local START_WEAPONS = { stick=true, sword=true }
local START_ARMORS  = { cloth=true, chain=true }

-- ########################
-- ## Helpers            ##
-- ########################
local function totalATK()
  return player.baseATK
    + (player.weapon and (player.weapon.atk or 0) or 0)
    + (player.armor  and (player.armor.atk  or 0) or 0)
end

local function totalDEF()
  return player.baseDEF
    + (player.weapon and (player.weapon.def or 0) or 0)
    + (player.armor  and (player.armor.def  or 0) or 0)
end

local function pushLog(text)
  table.insert(game.log, 1, text)
  if #game.log > 100 then table.remove(game.log) end
end

local function resetPlayerHP() player.hp = player.baseHP end

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

-- Grant loot defined on the monster entry.
-- Supports entries like "scimitar" (guaranteed) or {id="scimitar", chance=40} or {id="scimitar", chance=0.4}
local function normalizeChance(c)
  if not c then return 100 end
  if c <= 1 then return c * 100 end
  return c
end

-- In grantLootForMonster
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

  -- Look up the item object
  for _, it in ipairs(Items.weapons) do
    if it.id == gainedId then lootPopup.item = it end
  end
  for _, it in ipairs(Items.armors) do
    if it.id == gainedId then lootPopup.item = it end
  end

  -- Show loot as a temporary 'replacement' for the monster
  if lootPopup.item then
    lootPopup.visible = true
    lootPopup.timer = 0
    game.inBattle = false -- ensure no battle runs during loot
  end
end

end

local function spawnNextMonster()
  if game.monsterIndex >= #monsters then
    game.won = true
    pushLog("All monsters defeated! You win.")
    return
  end
  game.monsterIndex = game.monsterIndex + 1
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
  love.window.setMode(W, H, {resizable=true, minwidth=640, minheight=480})
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
end

function love.resize(nw, nh) W, H = nw, nh end

function love.update(dt)
  if game.inBattle and game.currentMonster and not game.won and not game.lost then
    game.battleTimer = game.battleTimer + dt
    if game.battleTimer >= game.turnInterval then
      game.battleTimer = 0
      if game.turn == "player" then
        local dmg = damage(totalATK(), game.currentMonster.def)
        game.currentMonster.hp = math.max(0, game.currentMonster.hp - dmg)
        pushLog(("You hit %s for %d!"):format(game.currentMonster.name, dmg))
        if game.currentMonster.hp <= 0 then
          pushLog(game.currentMonster.name .. " is defeated!")
          game.inBattle = false
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
end

-- ########################
-- ## UI Drawing         ##
-- ########################
local function drawBar(x,y,w,h, ratio)
  love.graphics.rectangle("line", x,y,w,h)
  love.graphics.rectangle("fill", x+2, y+2, (w-4) * math.max(0, math.min(1, ratio)), h-4)
end

local function drawStats()
  love.graphics.setFont(fonts.ui)
  local y = 10
  love.graphics.print("Player", 16, y); y = y + 22
  love.graphics.print(("HP: %d/%d"):format(player.hp, player.baseHP), 16, y); y = y + 18
  love.graphics.print(("ATK: %d"):format(totalATK()), 16, y); y = y + 18
  love.graphics.print(("DEF: %d"):format(totalDEF()), 16, y); y = y + 18

  -- Equipped names in yellow
  if player.weapon then love.graphics.setColor(1,1,0) end
  love.graphics.print("Weapon: ".. (player.weapon and player.weapon.name or "None"), 16, y); y = y + 18
  love.graphics.setColor(1,1,1)
  if player.armor then love.graphics.setColor(1,1,0) end
  love.graphics.print("Armor:  ".. (player.armor  and player.armor.name  or "None"), 16, y); y = y + 18
  love.graphics.setColor(1,1,1)

  return y
end

local function drawRoundBanner()
  local roundShown = (game.monsterIndex == 0) and 1 or game.monsterIndex
  love.graphics.setFont(fonts.title)
  love.graphics.printf(("Round %d / %d"):format(roundShown, #monsters), 0, 4, W, "center")
end

local function drawMonster()
  local topH = H * (1 - menuHeightFrac)

  local img, name

  if lootPopup.visible and lootPopup.item then
    -- Show loot image and name
    img = sprites.items[lootPopup.item.id]
    name = "You received: " .. lootPopup.item.name
  elseif game.currentMonster then
    -- Show monster image and name
    img = sprites.monsters[game.monsterIndex]
    name = game.currentMonster.name
  else
    return
  end

  -- Target visual box size (same for monster and loot)
  local maxW, maxH = 160, 120
  local x, y = W/2, topH/2 + 20

  -- Image scaling
  if img then
    local iw, ih = img:getDimensions()
    local scale = math.min(maxW / iw, maxH / ih)
    local drawX = x - (iw * scale) / 2
    local drawY = y - (ih * scale) / 2
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, drawX, drawY, 0, scale, scale)
  else
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", x - maxW/2, y - maxH/2, maxW, maxH, 8, 8)
  end

  -- Name/label
  love.graphics.setFont(fonts.ui)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(name, 0, y + maxH/2 + 10, W, "center")

  -- OK Button if loot is visible
  if lootPopup.visible then
    lootPopup.okButton = {
      x = W/2 - 50,
      y = y + maxH/2 + 40,
      w = 100,
      h = 30
    }
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", lootPopup.okButton.x, lootPopup.okButton.y, lootPopup.okButton.w, lootPopup.okButton.h, 6, 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.ui)
    love.graphics.printf("OK", lootPopup.okButton.x, lootPopup.okButton.y + 6, lootPopup.okButton.w, "center")
  end
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

  local textAreaW = w - 20 -- leave room for scrollbar
  local yy = y + 18

  for i = start, finish do
    love.graphics.printf(game.log[i], x, yy + (i-start)*lineH, textAreaW)
  end

  -- Scroll bar area
  local barX = x + textAreaW + 4
  local barY = y + 18
  local barH = h - 24
  local arrowH = 16
  local trackY = barY + arrowH
  local trackH = barH - arrowH * 2

  -- Store button hitboxes
  ui.logScrollUp = {x = barX, y = barY, w = 16, h = arrowH}
  ui.logScrollDown = {x = barX, y = barY + barH - arrowH, w = 16, h = arrowH}

  -- Draw up arrow
  love.graphics.rectangle("line", ui.logScrollUp.x, ui.logScrollUp.y, ui.logScrollUp.w, ui.logScrollUp.h)
  love.graphics.printf("^", ui.logScrollUp.x, ui.logScrollUp.y, ui.logScrollUp.w, "center")

  -- Draw down arrow
  love.graphics.rectangle("line", ui.logScrollDown.x, ui.logScrollDown.y, ui.logScrollDown.w, ui.logScrollDown.h)
  love.graphics.printf("v", ui.logScrollDown.x, ui.logScrollDown.y, ui.logScrollDown.w, "center")

  -- Draw track
  love.graphics.rectangle("line", barX, trackY, 16, trackH)

  -- Thumb (based on scroll position)
  if maxScroll > 0 then
    local thumbH = math.max(10, trackH * (visible / #game.log))
    local thumbY = trackY + (trackH - thumbH) * (scroll / maxScroll)
    love.graphics.rectangle("fill", barX + 1, thumbY, 14, thumbH)
  end
end


local function drawInventoryColumn(kind, x, menuY, colW, padding)
  local header = (kind == "weapons") and "Weapons" or "Armor"
  love.graphics.setFont(fonts.ui)
  love.graphics.print(header, x, menuY + padding)

  local list = items[kind]
  local itemH = 44     -- room for icon + text line
  local topY = menuY + padding + 24
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

    -- Icon scaled to ICON_SIZE
    local icon = sprites.items[it.id]
    if icon then
      local iw, ih = icon:getDimensions()
      local scale = math.min(ICON_SIZE/iw, ICON_SIZE/ih)
      love.graphics.draw(icon, r.x + 6, r.y + (itemH-ICON_SIZE)/2, 0, scale, scale)
    end

    -- Text
    local equipped = (r.kind == "weapon" and player.weapon and player.weapon.id == it.id)
                  or  (r.kind == "armor"  and player.armor  and player.armor.id  == it.id)
    if equipped then love.graphics.setColor(1,1,0) end
    local label = it.name .. " (".. (it.desc or "") ..")" .. (equipped and " [E]" or "")
    love.graphics.print(label, r.x + 6 + ICON_SIZE + 8, r.y + 10)
    love.graphics.setColor(1,1,1)

    table.insert(ui[buttonsKey], r)
  end

  if #list > maxVisible then
    love.graphics.setFont(fonts.small)
    love.graphics.printf("Mouse wheel to scroll", x, topY + maxVisible*itemH + 4, colW, "center")
  end
end

local function drawMenu()
  local menuY = H * (1 - menuHeightFrac)
  love.graphics.setFont(fonts.ui)
  love.graphics.rectangle("line", 0, menuY, W, H - menuY)

  local padding = 12
  local colW = (W - padding*3) / 3
  local x1 = padding
  local x2 = x1 + colW + padding
  local x3 = x2 + colW + padding

  -- Inventory columns
  drawInventoryColumn("weapons", x1, menuY, colW, padding)
  drawInventoryColumn("armors",  x2, menuY, colW, padding)

  -- Fight button / status
  ui.fightButton = {x=x3, y=menuY + padding, w=colW, h=44}
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
    fbLabel = ("Fight: Round ".. tostring(nextRound))
  end
  love.graphics.printf(fbLabel, ui.fightButton.x, ui.fightButton.y + 12, ui.fightButton.w, "center")

  -- Stats panel
  local panelY = ui.fightButton.y + ui.fightButton.h + 8
  local panelH = 90
  love.graphics.rectangle("line", x3, panelY, colW, panelH, 8, 8)
  love.graphics.print("Your Stats", x3 + 8, panelY + 6)
  love.graphics.print(("ATK %d  DEF %d"):format(totalATK(), totalDEF()), x3 + 8, panelY + 28)
  love.graphics.print("Tip: #2 needs a weapon, #3 needs weapon+armor.", x3 + 8, panelY + 50)

  -- Log panel
  local logY = panelY + panelH + 8
  local logH = (H - menuY) - (logY - menuY) - padding
  if logH > 40 then
    love.graphics.rectangle("line", x3, logY, colW, logH, 8, 8)
    drawLog(x3 + 8, logY + 8, colW - 16, logH - 16)
  end
end


function love.draw()
  love.graphics.clear(0.11,0.12,0.14)

  -- MAIN AREA
  local topH = H * (1 - menuHeightFrac)
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("line", 0, 0, W, topH)

  drawRoundBanner()
  local statsBottom = drawStats()
  drawMonster()

  -- HP bars under stats (avoid overlap)
  local barW = 220
  local playerBarY = statsBottom + 8
  drawBar(16, playerBarY, barW, 18, player.hp / player.baseHP)
  love.graphics.print("Player HP", 16, playerBarY + 22)
  if game.currentMonster then
    drawBar(W - barW - 16, playerBarY, barW, 18, game.currentMonster.hp / game.currentMonster.maxhp)
    love.graphics.print("Monster HP", W - barW - 16, playerBarY + 22)
  end

  -- MENU (bottom third)
  drawMenu()

  -- Footer
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
    return
  else
    return -- block other clicks
  end
end


  if button ~= 1 then return end
  if game.inBattle then return end -- disable equipping during auto battle

  -- Equip weapon
  if ui.weaponButtons then
    for _, r in ipairs(ui.weaponButtons) do
      if pointInRect(x, y, r) then
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

  -- Equip armor
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
  
    -- Log Scroll Up
  if ui.logScrollUp and pointInRect(x, y, ui.logScrollUp) then
    ui.logScroll = math.max(0, (ui.logScroll or 0) - 1)
    return
  end

  -- Log Scroll Down
  if ui.logScrollDown and pointInRect(x, y, ui.logScrollDown) then
    local logLines = #game.log
    local visible = 8 -- Should match drawLog calculation
    local maxScroll = math.max(0, logLines - visible)
    ui.logScroll = math.min(maxScroll, (ui.logScroll or 0) + 1)
    return
  end

  -- Fight
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
  local mx, my = love.mouse.getPosition()
  local menuY = H * (1 - menuHeightFrac)
  local padding = 12
  local colW = (W - padding*3) / 3
  local x1 = padding
  local x2 = x1 + colW + padding

  local listArea1 = { x = x1, y = menuY + padding, w = colW, h = H - menuY - padding }
  local listArea2 = { x = x2, y = menuY + padding, w = colW, h = H - menuY - padding }

  local function inArea(a)
    return mx >= a.x and mx <= a.x + a.w and my >= a.y and my <= a.y + a.h
  end

  if dy ~= 0 then
    if inArea(listArea1) then
      ui.weaponScroll = math.max(0, (ui.weaponScroll or 0) - dy)
    elseif inArea(listArea2) then
      ui.armorScroll  = math.max(0, (ui.armorScroll  or 0) - dy)
    end
  end
-- Detect if mouse is inside the log panel before scrolling it
local logY = H * (1 - menuHeightFrac) + 44 + 90 + 8 + 90 + 8  -- Matches panel layout
local logH = H - logY - 12
local colW = (W - 36) / 3
local x3 = 24 + colW * 2 + 24

local inLogArea = mx >= x3 and mx <= x3 + colW and my >= logY and my <= logY + logH
if inLogArea then
  local lineH = 16
  local visible = math.floor((logH - 24) / lineH)
  local maxScroll = math.max(0, #game.log - visible)
  ui.logScroll = math.max(0, math.min(maxScroll, (ui.logScroll or 0) + dy))  -- dy: up = positive
end

end

function love.keypressed(key)
  if key == "return" or key == "space" then
    if not game.inBattle then startBattle() end
  elseif key == "r" then
    -- Hard reset (keeps unlocked items if you added any via loot)
    game = {
      currentMonster=nil, monsterIndex=0, inBattle=false, battleTimer=0,
      turnInterval=0.45, turn="player", log={"Reset. Equip gear then press FIGHT."},
      won=false, lost=false
    }
    resetPlayerHP()
    player.weapon = nil
    player.armor = nil
  end
end

