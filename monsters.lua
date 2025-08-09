-- Module returning a list of monsters for each round.
-- Each entry includes "img" path pointing at a PNG in ./assets
-- Add optional `scale` to make specific monsters larger/smaller in the arena.

local M = {
  { name = "Slime",  maxhp = 10, atk = 1, def = 0, img = "assets/monsters/slime.png",  xp = 5, scale = 1.2,
    loot = {
      { id = "scimitar", dropChance = 0.10 },
      { id = "axe",      dropChance = 0.10 }}},
  { name = "Slime Lvl. 2",  maxhp = 20, atk = 3, def = 0, img = "assets/monsters/slime.png",  xp = 5, scale = 1.2,
    loot = {
      { id = "scimitar", dropChance = 0.5 },
      { id = "axe",      dropChance = 0.5 }}},
  { name = "Goblin", maxhp = 28, atk = 6, def = 2, img = "assets/monsters/goblin.png", xp = 5, scale = 1.3,
    loot = {
      { id = "Plain T-Shirt", dropChance = 0.9 }}},
  { name = "Ogre",   maxhp = 40, atk = 8, def = 4, img = "assets/monsters/ogre.png",   xp = 5, scale = 1.6 },
  { name = "SEAN BOSS", maxhp = 40, atk = 8, def = 1, img = "assets/monsters/sean.png", xp = 5, scale = 1.8 },
}

return M
