# Super Meat Bit
This is the repo for my Super Meat boy demake - Super Meat Bit
Written in assembly language for the NES

# To Run
Download the .nes file which will run on an NES emulator such as FCEUX (https://fceux.com/web/download.html)

# Controls
Left and right to run
A to Jump/Wall jump
B to reset

Collect all the bandages in the fastest time you can

## Description
Since this was part of a university project, time constraints meant there is no multi-level play, however this would be a fun continuation of the development to continue with in the future as a lot of the hardest challenges, such as colision and sprite switching, have been solved within this minigame.

I'm especially pleased to have achieved my stretch goal within this project of blood-permenance on the spikes which I achieved by laying out the blood spikes on the sprite sheet (on odd numbered tiles) next to their clean counterparts (on even numbered tiles). On collision, the sprite changes when on an even tile, causing the blood effect. To develop this further I could have a gradually increasing colour over any number of tiles and using a similar concept with the check being the remainder of however many variations. e.g. clean on 0, small splat on 1, larger splat on 2, covered on 3.
