-- monsters.lua
-- Module returning a list of monsters for each round.
-- Each entry includes "img" path pointing at a PNG in ./assets

local M = {
  { name = "Slime", maxhp = 15, atk = 3, def = 0, img = "assets/monsters/slime.png",
  loot = {
      { id = "scimitar", dropChance = 0.5 },
      { id = "axe", dropChance = 0.5 }}},
  { name = "Goblin", maxhp = 28, atk = 6, def = 2, img = "assets/monsters/goblin.png" },
  { name = "Ogre",   maxhp = 40, atk = 8, def = 4, img = "assets/monsters/ogre.png" },
  { name = "SEAN BOSS",   maxhp = 40, atk = 8, def = 1, img = "assets/monsters/sean.png" },
}

return M