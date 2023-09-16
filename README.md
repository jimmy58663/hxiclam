# hxiclam
This is an Ashita v4 addon that acts as a tracker for clamming in FFXI; specifically developed for HorizonXI server. This addon is modeled after hgather by SlowedHaste https://github.com/SlowedHaste/HGather.


## Commands
/hxiclam - Opens the configuration menu

/hxiclam open - Opens the window showing clamming data

/hxiclam close - Closes the window showing clamming data

/hxiclam update - Updates the pricing and weight for items based on the item pricing and item weights in the editor

/hxiclam update pricing - Updates the pricing for items based on the item pricing in the editor

/hxiclam update weights - Updates the weight for items based on the item weights in the editor

/hxiclam report - Prints the clamming data to chatlog

/hxiclam clear bucket - Clears the clamming bucket data

/hxiclam clear session - Clears the clamming session data

/hxiclam clear - Clears the clamming bucket and session data

## Pricing
Pricing for items is listed in the configuration window under the Item Price tab. Make sure the format is as follows:

**Format:** itemname:itemprice

**Example:** pebble:100

This would price pebbles at 100g.  Make sure there are no spaces or commas in any of the lines and the text is in lowercase.

If you update the prices while in game, make sure to use the **/hxiclam update** or **/hxiclam update pricing** command to update the prices.

## Weights
Weights for items are listed in the configuration window under the Item Weight tab. Make sure the format is as follows:

**Format:** itemname:itemweight

**Example:** pebble:7

This would set the weight for pebbles at 7 pz. Make sure there are no spaces or commas in any of the lines and the text is in lowercase.

If you update the weights while in game, make sure to use the **/hxiclam update** or **/hxiclam update weights** command to update the weights.

##Contact Info
If you would like to contact me for anything you can leave an issue on this repo or utilize the below methods.
HorizonXI: Cybin
HorizonXI Discord: Cybin  https://discord.gg/horizonxi
