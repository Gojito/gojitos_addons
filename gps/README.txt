gps 1.23
by gojito
For CatsEyeXI on Ashita 4.

Shows your X, Y and Z, and routes you to a spot with a turn arrow, the
distance and an up or down cue.


INSTALL

1. Copy the "gps" folder into Ashita\addons\
2. In game:  /addon load gps
3. Type /gps to show the HUD.
4. Once per steering mode: /gps calib, then run straight forward a few
   steps. That zeroes the arrow.

To load it every time, add this line to Ashita\scripts\default.txt:

    /addon load gps


COMMANDS

/gps                  show or hide the HUD
/gps go <name>        route to a saved spot or a built-in spot of this
                      zone (part of the name is enough)
/gps find <text>      search this zone for a name
/gps list             your saved spots
/gps list <type>      this zone's built-in spots: all, npc, nm, coffer,
                      chest, statue or door
/gps save <name>      save where you stand
/gps del <name>       delete a saved spot
/gps dest <x> <z>     route to a point in this zone
/gps here             mark where you stand
/gps waypoint <zone> <x> <y> <z> <label>
                      route to a point; in another zone it waits and
                      routes once you zone in
/gps clear            clear the destination
/gps print            your X, Y and Z in chat
/gps compact          hide the HUD's title bar
/gps mode camera      steer by where the camera looks (the default)
/gps mode character   steer by where you face
/gps calib            zero the arrow: run this, then run forward
/gps flip             the arrow turns the wrong way
/gps vflip            the up or down cue reads backwards
/gps camprobe         check the camera read
/gps help             the command list


GOOD TO KNOW

- gps sends nothing to the server. It reads your position, heading and
  zone, and the camera, from the client.
- Named NPCs and doors, Dynamis NMs and statues, and treasure chest and
  coffer spots are built in, so /gps go works without saving anything.
- Another addon can route you with /gps waypoint. Quester's Go button
  does.


FILES IT WRITES

Ashita\config\addons\gps\
    gps_cfg.lua      steering mode, calibration and look
    saved_gps.lua    your saved spots

A gps_cfg.lua or saved_gps.lua that gps 1.22 or older left in the gps
folder is copied there once and left in place.


CREDITS

The built-in spots come from the CatsEyeXI server source, which is
based on LandSandBoat and licensed under the GNU GPL v3. The camera
read follows the fancycompass addon.
