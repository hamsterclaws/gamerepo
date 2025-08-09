Stat Fighter (Template)
=======================

How to run:
1) Install LÖVE 11.x from https://love2d.org/
2) Put this whole folder somewhere (e.g. U:\love2d\MYGAMES\StatFighter)
3) Run: love "StatFighter"   (or drag the folder onto love.exe)

What’s inside:
- main.lua        -> game loop, UI, drawing, input
- items.lua       -> starting items (weapons/armor) with image paths
- monsters.lua    -> monster list with image paths
- assets/         -> placeholder PNGs (replace with your real art)
    - items/*.png
    - armor/*.png
    - monsters/*.png

Notes:
- To add more monsters: edit monsters.lua and append entries.
- To add new items: edit items.lua (add `img` pointing at a PNG in assets).
- Loot examples are in `grantLootForRound` inside main.lua.
- Inventory lists are scrollable with the mouse wheel.
- Click an item to equip/unequip (not allowed during battle).