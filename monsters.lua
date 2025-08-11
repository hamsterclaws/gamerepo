-- Module returning a list of monsters for each round.
-- Each entry includes "img" path pointing at a PNG in ./assets
-- Add optional `scale` to make specific monsters larger/smaller in the arena.

local M = {
  { name = "Slime Lvl. 1",  maxhp = 10, atk = 1, def = 0, img = "assets/monsters/slime.png",  xp = 5, scale = 1.2,
    loot = {
      { id = "woodClub", dropChance = 0.10 },
      { id = "Plain T-Shirt",      dropChance = 0.90 }}},
  { name = "Slime Lvl. 2",  maxhp = 20, atk = 3, def = 0, img = "assets/monsters/slime.png",  xp = 7, scale = 1.2,
    loot = {
      { id = "woodClub", dropChance = 0.10 },
      { id = "tshirt",      dropChance = 0.10 }}},
  { name = "Slime Lvl. 3",  maxhp = 20, atk = 3, def = 0, img = "assets/monsters/slime.png",  xp = 10, scale = 1.2,
    loot = {
      { id = "woodClub", dropChance = 0.10 },
      { id = "tshirt",      dropChance = 0.10 }}},
  { name = "Slime Lvl. 4",  maxhp = 25, atk = 3, def = 0, img = "assets/monsters/slime.png",  xp = 10, scale = 1.2,
    loot = {
      { id = "woodClub", dropChance = 0.10 },
      { id = "tshirt",      dropChance = 0.10 }}},
  { name = "Slime Lvl. 5",  maxhp = 30, atk = 4, def = 1, img = "assets/monsters/slime5.png",  xp = 15, scale = 1.2,
    loot = {
      { id = "woodClub", dropChance = 0.10 },
      { id = "tshirt",      dropChance = 0.10 }}},
  { name = "Goblin", maxhp = 28, atk = 6, def = 2, img = "assets/monsters/goblin.png", xp = 5, scale = 1.3,
    loot = {
      { id = "Plain T-Shirt", dropChance = 0.9 }}},
  { name = "Ogre",   maxhp = 40, atk = 8, def = 4, img = "assets/monsters/ogre.png",   xp = 5, scale = 1.6 },
  { name = "SEAN BOSS", maxhp = 40, atk = 8, def = 1, img = "assets/monsters/sean.png", xp = 5, scale = 1.8 },
}

return M
