# hxiclam
This is an addon that acts as a tracker for clamming in FFXI; specifically developed for HorizonXI server. It is available for both Ashita v4 and Windower. Make you just need to download the proper version from the releases.

The addon is more complete in the Ashita version due to originally being developed there and my familiarity with the platform. Both versions provide tracking of clamming results, during a session and your current bucket. Weights and prices can be adjusted in the appropriate settings for more accurate tracking.

All existing items in HorizonXI's clamming pool are included in the default settings, but if something is ever missing it can be added in the settings.

To install, copy the relevant hxiclam.lua file from your chosen framework's directory to the main hxiclam directory, and copy the constants.lua file from the shared directory to the main hxiclam directory. Then load in game with /addon load hxiclam.

## Screenshots
### Ashita v4
![Alt text](/Media/hxiclam_1.png?raw=true)

### Windower
![Alt text](/Media/hxiclam_windower_1.png?raw=true)

## Questions
If you are having issues or have any questions you can try the [Wiki](https://github.com/jimmy58663/hxiclam/wiki "HXIClam WIki").
My contact info is listed in the Wiki also for anything that you still need help with.

## Ignored Chat Channels
To stop other players from griefing I have attempted to filter out chat channels that accept user input. Known chat channels filtered:

| Channel | Send ID | Receive ID |
| --- | ---: | ---: |
| Say | 1 | 9 |
| Shout | 2 | 10 |
| Yell | 3 | 11 |
| Tell | 4 | 12 |
| Party | 5 | 13 |
| Linkshell | 6 | 14 |
| Command Error |  | 157 |
| Linkshell 2 |  | 214 |
| Unity |  | 212 |
| Assist JP |  | 220 |
| Assist EN |  | 222 |

If you find additional channels that are causing issues, whether you know the name or the mode, please [open an issue](https://github.com/jimmy58663/hxiclam/issues) with the details.
