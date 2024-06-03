# hxiclam
This is a Windower addon that acts as a tracker for clamming in FFXI; specifically developed for HorizonXI server.

## Screenshots

![Alt text](../Media/hxiclam_windower_1.png?raw=true)

![Alt text](../Media/hxiclam_windower_2.png?raw=true)

![Alt text](../Media/hxiclam_windower_3.png?raw=true)

## Commands
//hxiclam show - Shows the hxiclam window

//hxiclam show session - Shows the session stats in the hxiclam window

//hxiclam show summary - Shows the HXIClam session summary

//hxiclam hide - Hides the hxiclam window

//hxiclam hide session - Hides the session stats in the hxiclam window

//hxiclam reload - Reloads settings from the hxiclam/data/settings.xml file. This includes updating the pricing and weight for items based on the item pricing and item weights in the file

//hxiclam clear - Clears the clamming bucket and session data

//hxiclam clear bucket - Clears the clamming bucket data

//hxiclam clear session - Clears the clamming session data

## Pricing
Pricing for items is listed in item_index at hxiclam/data/settings.xml. Make sure the format is as follows:

**Format:** itemname:itemprice

**Example:** pebble:100

This would price pebbles at 100g.  Make sure there are no spaces or commas in any of the lines and the text is in lowercase.

If you update the prices while in game, make sure to use the **//hxiclam reload** command to update the prices.

## Weights
Weights for items are listed in item_weight_index at hxiclam/data/settings.xml. Make sure the format is as follows:

**Format:** itemname:itemweight

**Example:** pebble:7

This would set the weight for pebbles at 7 pz. Make sure there are no spaces or commas in any of the lines and the text is in lowercase.

If you update the weights while in game, make sure to use the **/hxiclam reload** command to update the weights.

## Questions
If you are having issues or have any questions you can try the [Wiki](https://github.com/jimmy58663/hxiclam/wiki "HXIClam WIki").
My contact info is listed in the Wiki also for anything that you still need help with.
