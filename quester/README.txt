Quester 1.3.1
by gojito
For CatsEyeXI on Ashita 4.

Tells you the next step of a quest or mission, so you can pick one up
where you left off.


INSTALL

1. Copy the "quester" folder into Ashita\addons\
2. Copy the "gps" folder into Ashita\addons\ too. Quester's Go button
   needs gps 1.22 or newer. If you already have gps, replace gps.lua and
   the data folder, and keep your own gps_cfg.lua and saved_gps.lua.
3. In game:  /addon load gps
             /addon load quester
4. Zone once. The game only sends your quest log when you zone.
5. Type /qr


LOAD IT EVERY TIME (recommended)

Add these two lines to Ashita\scripts\default.txt, next to the other
"/addon load" lines, gps first:

    /addon load gps
    /addon load quester

Quester keeps a journal of the scenes, trades and kills it sees. It can
only record while it is loaded, so loading it at startup means it never
misses a step.


COMMANDS

/qr               open or close the window
/qr <name>        one line answer for that quest or mission (part of
                  the name is enough)
/qr go <name>     route to that step with gps
/quester          same as /qr


THE WINDOW

Active Quests       quests in your log, grouped by area
Active Missions     one row per storyline you are on
Available Quests    quests you can start now, and who starts them
Available Missions  the next mission of each storyline

Click a row to see its steps. Go routes you there with gps. If the step
is in another zone, gps holds it and routes when you zone in.
Drag the line above the steps to resize them.


GOOD TO KNOW

- Read only. Quester sends nothing to the server.
- A quest you started before installing Quester may show "2 possible"
  or "Up to 19 left". The game does not tell the client which step you
  are on, so Quester narrows it down from your key items, your items and
  what its journal sees from now on. Do one step and it catches up.
- Fame is not known to the client. A quest that needs fame is listed
  with a note, never hidden.
- Built for the CatsEyeXI server as of 2026-10-15. After a server update
  that changes quests, get a newer Quester.
- /quest still opens the game's own quest log.


FILES IT WRITES

Ashita\config\addons\quester\
    <Character>_journal.txt   what it has seen you do
    <Character>_log.txt       your last quest log
    <Character>_check.txt     a checkpoint so loading is fast
    <Character>_window.lua    window position and size
    <Character>_<date>.log    diagnostics

They stay on your PC. To start over, delete that folder.


CREDITS

Quest and mission steps are generated from the CatsEyeXI server source,
which is based on LandSandBoat and licensed under the GNU GPL v3.
