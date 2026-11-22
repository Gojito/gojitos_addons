# gojito's addons

Ashita 4 addons for CatsEyeXI. Each folder is one addon and copies straight into place.

| Addon | Version | What it does |
|---|---|---|
| [gps](gps) | 1.23 | Shows your X, Y and Z, and routes you with a turn arrow, the distance and an up or down cue to a saved spot, an NPC or door, or a point another addon sends |
| [quester](quester) | 1.3.1 | Tells you the next step of a quest or mission; its Go button routes you there with gps |

## Installing

| Client | Copy the folders into | Then |
|---|---|---|
| Ashita 4 | `Ashita\addons\` | `/addon load gps`, then `/addon load quester` |
| VanaCore | `Vanacore\addons\ashita\` | The same |

Quester needs gps. After loading quester, zone once: the game sends your quest log only when you zone. Each folder's
README.txt lists its commands and the files it writes.

## What they read and send

| Addon | Reads | Sends |
|---|---|---|
| gps | Your position, heading and zone, and the camera, from the client | Nothing |
| quester | Your quest and mission log, key items and items, and the scenes, trades and kills it sees | Nothing to the server; Go types one `/gps waypoint` command |

## Data

| Folder | Made from |
|---|---|
| `gps/data/` | The CatsEyeXI server's NPC list, Dynamis spawns and treasure spots, plus five NM spawns added by hand |
| `quester/data/` | The CatsEyeXI server's quest and mission scripts, with names from the game client |

Both come from the server at commit `b641b20849` (2026-10-15).

## License

GNU GPL v3 or later; see [LICENSE](LICENSE). The data is made from the CatsEyeXI server source, which is GPL v3 too.
