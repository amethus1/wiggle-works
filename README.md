# 🫧 Wiggle Works

A physics sandbox and battle simulator made in **Godot 4.7**. Drop in **stick-figure soldiers, knights, ninjas, animals and dinosaurs**, give them swords, guns and armor, put them on teams and watch them fight. Blow everything up with grenades, C4, napalm and nukes, build platforms and forts, and dig lava pits and acid vats. There's also a **3D battlefield** you watch from above at an angle (isometric view), plus the squishy **Wigglies**, toys and machines, twelve worlds, stickers, and play together with friends on the same Wi-Fi.

It stays cartoony: no blood. Knocked-out fighters get X eyes and spinning stars.

## Play it

### Install on Windows

1. Open **https://github.com/amethus1/wiggle-works/releases/latest** and, under **Assets**, click **WiggleWorks-Windows.exe**. If the browser says the file isn't commonly downloaded, choose **Keep**.
2. Make a folder for it, for example **Documents\Wiggle Works**, and move the `.exe` there. Don't use Program Files: the game updates itself, so it needs a folder it's allowed to change.
3. Double-click it. The first time, Windows may say **"Windows protected your PC"** because the game isn't signed. Click **More info → Run anyway**.
4. To play together over Wi-Fi, click **Allow** if Windows Firewall asks.
5. For a desktop icon, right-click the `.exe` → **Show more options → Send to → Desktop (create shortcut)**.

### Updates

When the game starts, it asks GitHub whether there's a newer version. If there is, **✨ New version!** pops up. **⬇️ Update now** downloads it, checks it arrived whole, swaps it in and restarts the game; **Later** skips it until next time. **⚙️ Me → 🔄 Updates** has **Check for updates now** and a switch to stop checking when the game starts. The title screen shows the version in the bottom corner.

On a Mac, the update button opens the download page instead.

### Other ways

- **Mac:** download **WiggleWorks-Mac.zip** from the same page (or unzip `build/mac/Wiggle Works.zip`), then **right-click Wiggle Works.app → Open**. Double-clicking the first time says it can't check the developer, because the app isn't signed by Apple.
- **Windows, without the internet:** copy `build/windows/Wiggle Works.exe` to the other computer and run it.
- **From the project:**
  ```bash
  godot --path .            # title screen
  godot -e --path .         # open it in the Godot editor
  ```

## Fighters

Open the **Toy Box** (Tab) and pick **People**, **Animals** or **Dinos**. Before placing one, choose its **team** and **personality** at the top of the Toy Box.

- **People:** Stick Figure, Soldier (rifle), Knight (sword and shield), Viking (axe), Archer (bow), Sniper, Rocketeer (bazooka), Grenadier, Gunner (machine gun), Medic (heals teammates), Ninja (katana) and Giant (big hammer).
- **Animals:** Dog, Wolf, Bear, Bull, Elephant and Chicken.
- **Dinos:** T-Rex, Raptor, Triceratops, Stegosaurus, Brachiosaurus and Pterodactyl (flies).

**Teams:** 🔴 Red, 🔵 Blue, 🟢 Green, 🟡 Yellow and 🐾 Wild. Wild beasts fight everyone. Teammates never hurt each other.

**Personalities:**

| Personality | What it does |
|---|---|
| ⚔️ Attack | Charges the nearest enemy |
| 🛡️ Defend | Guards the spot where you placed it and fights whoever comes close |
| 🏹 Ranged | Keeps its distance and shoots |
| 😡 Berserk | Runs in fast and hits hard, never retreats |
| 😱 Coward | Runs away when it's hurt |
| 🌼 Peaceful | Never starts a fight |

**Start the battle** with the **⚔️ button** at the top of the screen. Press it again to pause the fighting while you set things up. When only one team is left, it wins: 🏆 and confetti!

**What you can do with a fighter (click it to select it):**
- **Play as it:** A/D to walk, W to jump, aim with the mouse, click or hold F to attack. Esc stops.
- **Arm it:** drag a weapon or armor onto a person, or select the weapon and press **Give**. When a person gets back up with empty hands, they grab a weapon lying nearby.
- Change its team or personality, revive it, resize, copy or delete it.
- Grab and throw it. It goes floppy and gets back up a moment later, unless it was knocked out.

### Weapons and armor

- **🗡️ Weapons:**
  - Melee: sword, katana, axe, spear, war hammer, club and laser sword.
  - Guns: pistol, rifle, shotgun, machine gun, sniper rifle and laser blaster.
  - Others: bazooka (rockets), bow (arrows), flamethrower and a bag of grenades.
- **🛡️ Armor:** helmet, body armor and shield. Each one blocks part of every hit.

### Explosives and hazards

- **💣 Booms:**
  - Grenade, dynamite, C4 (double-click or press F to set it off) and landmine (goes off when stepped on).
  - Explosive barrel, cluster bomb, napalm (leaves fire), acid bomb, and the ☢️ **Nuke**. The nuke counts down, then flattens everything.
- **🌋 Hazards:** lava pit, acid vat and water tank. Lava sets things on fire, acid fizzes them, and water puts fires out.
- **💣 button (top bar):** sets off every C4 in the world at once.
- **✨ Magic:** Airstrike, Artillery, Meteor Shower and Heal Everyone.

### Platforms

Pick the **🏗️ Platform** tool (**P**), choose wood, metal, stone or concrete, then **drag a rectangle** to build a platform. Explosions don't move platforms. The Toy Box **Platforms** tab has ready-made pieces: small and big platforms, wall, tower, bunker and bridge. Erase a platform with the 🧽 Eraser.

## ⚔️ 3D Battle

Click **⚔️ 3D Battle** on the title screen. It's a 3D battlefield you look down on at an angle (isometric view). Place armies, animals and dinosaurs, press **▶ Fight!** and watch them battle it out. Fighters get blasted into the air, fly all over the place, and land as floppy ragdolls. They get back up unless they've been knocked out.

1. Pick something in the **Toy Box** on the left (People, Animals, Dinos, Vehicles, History, Booms, Hazards or Build).
2. For fighters, choose a **team** color, a **mood** and a **size** (🐜 Tiny, Normal, Big or 🦖 Huge). ✨ Auto lets each fighter do what it's best at. Big fighters are tougher, heavier and harder to knock over.
3. Click the ground to place one. **Drag** to place a whole line, and **Shift-drag** for a big block.
4. Press **▶ Fight!** (Space). The team counts at the top right show who's left, and the last team standing wins. 🏆

**What's in it:**
- **New in 3D only:**
  - 🧙 **Wizard:** casts fireballs that set things alight.
  - 🤖 **Robot:** an armored laser blaster that falls apart into tin pieces.
  - 🦍 **Gorilla:** punches, ground-pounds and throws boulders.
  - 🦣 **Mammoth:** charges with its tusks.
  - 🐉 **Dragon** (in the Dinos tab): flies, circles and breathes fire.
- **🚜 Vehicles:** each is painted in its team color, and you can drive or fly every one of them (see Play as a fighter).
  - **Tank:** turret cannon plus a small machine gun.
  - **Jeep:** a fast machine-gun jeep that runs people over.
  - **🏎️ Race Car:** no gun, just speed. Fighters it rams go flying with a "BONK!", and it honks.
  - **🚁 Helicopter:** spinning rotors, a swivelling chin gun and rocket pods. It hovers, circles and shoots.
  - **🛩️ Fighter Plane:** a propeller fighter that starts in the air, makes strafing dives and bomb runs, and dogfights other aircraft.
  - **Cannon:** lobs cannonballs from far away.
  - **MG Turret:** a sandbag machine-gun nest.

  Bullets bounce off vehicles, but rockets and bombs hurt. Big blasts flip them, and they bounce back onto their wheels. When destroyed they blow apart into smoking pieces; shot-down aircraft trail smoke, spin down and crash. You can pick ground vehicles up with ✋ Grab and drop them somewhere else.
- **People, animals and dinos:** the same 24 as the 2D game, as chunky 3D models with their own moves:
  - Knights block with their shields and medics heal their friends.
  - Ninjas dodge, and snipers aim with a red laser.
  - Bulls and triceratops charge, the T-Rex roars and tosses things, and pterodactyls swoop.
- **💣 Booms:** grenade, dynamite, C4 (press 💥 Detonate or **B**), landmine, boom barrel (they set each other off), cluster bomb, napalm, acid bomb, ✈️ airstrike, ☄️ artillery and the ☢️ **NUKE**. The nuke makes a white flash, shock rings and a mushroom cloud, knocks over whole armies, and flattens buildings.
- **🌋 Hazards:** lava pool, lava lake, acid pool and acid swamp. Drag to make them bigger. Fighters walk around them (unless they're berserk). Anything that falls in sinks with a sizzle.
- **🧱 Build:** block, wall, ramp, tower (archers can stand on top), bunker, bridge, sandbags and crates. Explosions knock buildings apart, and pieces with nothing under them fall.
- **🗺️ Maps** (each is 384 m across, with hills, forests, dirt roads, lakes and farms around the middle, and mountains or the sea on the horizon):
  - Grassland, Desert, Snow and Volcano (8 lava pools and a smoking volcano).
  - 🌾 **Farmland:** striped fields, fences, stone walls, barns and a windmill.
  - 🏖️ **Beach:** the sea on one side, sand, then bluffs with gullies, fields and a village.
  - ⛰️ **Mountain Pass:** a narrow valley between tall cliffs that opens out at each end.
  - 🏘️ **Town:** a square, a street grid, about 150 buildings and a church.

**🎮 Play as a fighter or vehicle:** select one and press **🎮 Play as me!** (or **P**).
- **WASD** moves and the **mouse** aims. **Click** (or hold F) to attack, and press **Space** to jump.
- Click on an enemy to lock on. Click the ground to shoot at that spot.
- The camera follows you, and a spinning ring marks your fighter. **Esc** hands it back to the computer.
- **👀 First person (V):** look out of its eyes. The mouse looks around, W walks where you're looking, and a crosshair shows where your shots go. You see your own weapon in your hands. Fighters standing right in front of your face fade away so they don't block the view. Press **V** again for the overhead view. If you get knocked out (or your vehicle is wrecked), you jump straight into the nearest teammate and keep going: a fighter takes over before a vehicle does. When nobody is left on your team, you go back to the overhead view. Playing overhead, a knock-out just goes back to watching.
- **Driving and flying** (both views; the help line at the top shows the keys for what you're in):

  | Vehicle | Overhead view | First person |
  |---|---|---|
  | Tank, jeep | WASD drives, the turret follows the mouse | W/S gas and reverse, A/D steer, the turret follows the crosshair |
  | Race car | WASD drives, Space or click honks | W/S gas and reverse, A/D steer |
  | Helicopter | WASD flies, Space/Shift up and down, the nose follows the mouse | W/S forward and back, A/D sidestep, the mouse turns, Space/Shift up and down |
  | Fighter plane | flies to the mouse and circles it, Space/Shift change height | steers to where you look, W/S throttle |
  | Cannon, MG turret | aim with the mouse | aim with the crosshair |

  Click fires the main weapon and right-click the other one (machine gun, rockets, or a bomb from the plane). In first person you sit in the driver's seat, the tank hatch or the cockpit.

**🎥 Follow (F):** keeps the camera on any fighter you select, so you can watch it battle. Moving the camera stops following.

**⚙️ Battle Rules** (the top bar; it lights up when you've changed something). Your choices are remembered:

| Rule | Choices |
|---|---|
| 🌍 Gravity | Normal, 🌙 Moon, 🪐 Floaty, 🪨 Heavy. Low gravity makes blasts send everyone sky-high. |
| 💥 Explosions | Normal, Big, ☄️ MEGA |
| 💨 Knockback | Normal, Big, 🌪️ Crazy |
| ❤️ Toughness | 🥚 Fragile, Normal, 💪 Tough, 🦾 Super |
| 👟 Fighter speed | 🐌 Slow, Normal, ⚡ Fast |
| 🤝 Blasts hurt teammates | Yes / No |
| ♾️ Reinforcements | Off / Endless battle (knocked-out fighters come back where you placed them) |
| 🌞 Time of day | Day, 🌅 Sunset, 🌙 Night (explosions and gunfire light up the dark) |
| 🌦️ Weather | Clear, 🌧️ Rain, 🌨️ Snow |
| 📳 Screen shake | Off, A little (the start), 📳 Lots. Small bumps and gunfire never shake the screen. ↺ Back to normal leaves this one alone. |

**🎲 Surprise Battle:** builds a random battle and starts it a moment later. You get a random map, 2–4 equal armies (soldiers, knights and vikings, animals, dinosaur attacks, or total chaos), plus some cover, barrels, mines and maybe a lava pool.

**⏮ Reset:** when you press Fight!, the game remembers where everything was. **⏮** (next to Fight!) or **⏮ Play it again** on the winner screen puts every fighter, vehicle, building, barrel and pool back, ready to play the same battle again.

**💾 Save:** six save slots. Each keeps the whole battle: map, rules, fighters (with their team, mood, size and health), buildings, barrels, C4, mines and pools. Saving during or after a fight saves the setup from when you pressed Fight!, so loading it gives you the same battle to play again.

**📜 History:** press **📜** in the top bar to pick a real battle from long ago. Each one comes with a short, true story and what to watch for. It sets up both armies in their real formations, with the walls, stakes, earth forts, fences, beach obstacles and landing boats, then waits for you to press **Fight!** (or pick a soldier to play).

| Battle | Year | Sides | Map |
|---|---|---|---|
| 🏛️ Thermopylae | 480 BC | Spartans and Greeks hold a narrow pass against the Persians | Mountain Pass |
| 🦅 Alesia | 52 BC | Romans behind their walls against the Gauls | Grassland |
| 👑 Hastings | 1066 | a Saxon shield wall on a hill against Norman knights and archers | Grassland |
| 🏹 Agincourt | 1415 | English longbowmen behind sharpened stakes against French knights in the mud | Farmland |
| 🎩 Bunker Hill | 1775 | redcoats march uphill against the militia's earth fort | Grassland |
| 🎖️ Waterloo | 1815 | British squares against French cavalry and cannons | Farmland |
| 🧢 Gettysburg | 1863 | Pickett's Charge: Union behind a stone wall against Confederate lines | Farmland |
| ✈️ Battle of Britain | 1940 | a dogfight between fighter planes | Grassland |
| 🌊 D-Day: Omaha Beach | 1944 | troops and tanks land on a beach against bunkers | Beach |
| ❄️ Battle of the Bulge | 1944 | tanks and soldiers in the snowy woods | Snow |

The **📜 History** Toy Box tab has the 14 soldiers they use, so you can put them in your own battles too: hoplite, Persian immortal, Roman legionary, Gaul, Saxon, longbowman, knight on horseback, redcoat, minuteman, line infantry, cavalry, Union and Confederate soldiers, and a WWII GI. Muskets fire together in big smoky volleys and switch to bayonets up close; horsemen charge, and when knocked over, horse and rider tumble separately. There are no flags or symbols, just team colours.

**👥 Play together:** see below.

**⭐ MVP:** when a team wins, the fighter with the most knock-outs is named MVP.

**Tools** (the bar at the bottom):
- **➕ Place (1):** put things on the battlefield.
- **🔍 Select (2):** click a fighter to see its health and change its team or mood. You can also 🚀 launch it, 💚 heal it or 🗑️ remove it.
- **✋ Grab (3):** pick up any fighter or barrel and fling it.
- **🧽 Eraser (4):** remove things.

**Keys:**

| Key | What it does |
|---|---|
| Space | Fight / pause |
| G | Slow motion |
| Tab | Hide or show the Toy Box |
| P | Play as the selected fighter or vehicle (Esc stops) |
| V | First person / overhead view while playing |
| F | Follow the selected fighter with the camera |
| Q / E | Turn the camera |
| R | Turn the building you're placing |
| B | Set off all the C4 |
| WASD, arrows, or right-drag | Move the camera |
| Mouse wheel or pinch | Zoom |
| Delete | Remove the selected fighter |
| H | Help |

**🧹 Clear** removes knocked-out fighters and rubble, all fighters, or everything. **🏠** goes back to the title screen.

**👥 Play together (3D):** friends on the same Wi-Fi can play the same battle, each on their own computer.
- One person presses **👥 → 🏠 Host**. The others open 3D Battle, press **👥** and click the host's battle in the list (or type the host's address).
- Everyone sees the same battle. Friends can place things from the Toy Box, erase, press Fight!, Pause and ⏮ Reset, and play their own fighter or vehicle, in first person too. Names float over the fighters people are playing.
- Only the host can change the map, rules, saves, History and Surprise battles, or ✋ grab things.
- The host's computer runs the real battle and sends a snapshot about 20 times a second. Friends' computers show copies that glide to where the host says, and their keys and mouse go back to the host.

## The Wigglies

Each Wiggly is a soft jelly body that springs back into shape. Pull one too hard and it **pops into two**. Drop a Wiggly onto one of the same kind to **combine** them into a bigger one. Select one and press **Play** (or **C**) to control it.

| Wiggly | Special move (F) |
|---|---|
| 🔵 Bloop | Super Bounce: a huge jump |
| 🟢 Gummy | Sticky Mode: sticks to whatever it touches |
| 🟡 Zappy | Zap!: powers machines and jiggles friends |
| 🟠 Blaze | Flame Puff: lights fireworks and booms, melts ice |
| 🩵 Frosty | Frost Breath: freezes things where they are, even in mid-air |
| 🩷 Puffy | Puff Up: grows big and floats away |
| ⚪ Boulder | Ground Pound: slams down and knocks everything back |
| 🟣 Twinkle | Twinkle Warp: teleports in a flash |

## Toys (Toy Box)

- **⚽ Balls:** beach ball, super bouncy ball, soccer ball, bowling ball, marble, steel ball.
- **🧱 Blocks:** wood block, long plank, brick, letter block, glass pane, ice cube, pillow, ramp, metal beam.
- **⚙️ Machines:**
  - Power sources: battery, switch, big button, blinky timer.
  - Machines they power: lamp, bell, fan, magnet, motor wheel, rocket booster, propeller, conveyor belt, ball cannon, bubble maker.
  - Spring pad (no power needed).
- **🎆 Booms:** confetti popper, firework, paint bomb, bubble bomb, glue bomb, freeze bomb, boom barrel, mega boom.
- **🚗 Rides:** go-kart, monster truck, balloon, hot air balloon, hover saucer (with a tractor beam), sail boat.
- **🛠️ Builds** (ready-made contraptions): see-saw, catapult, spinny wheel, rocket cart, domino run, light show.

The Toy Box also has the fighter tabs (People, Animals, Dinos), Weapons, Armor, Hazards and Platforms, described above.

## Tools

| Key | Tool | What it does |
|---|---|---|
| 1 | ✋ Grab | Drag and throw. Double-click a toy to use it. Hold Shift to move a whole Wiggly. |
| 2 | 🧴 Glue | Drag from one thing to another to stick them together |
| 3 | 📍 Hinge | Joined, but free to spin (great for wheels and see-saws) |
| 4 | 🪢 Rope | Tie things together |
| 5 | 🌀 Spring | A bouncy connection |
| 6 | 🔌 Wire | Battery, switch, button or timer → machines. Power flows through wires, and an off switch blocks it. |
| 7 | 🎨 Paint | Pick a color, then click things |
| 8 | 🔍 Resize | Click to grow, Shift-click or right-click to shrink |
| 9 | 📌 Nail | Nail a toy in place |
| 0 | 🧽 Eraser | Click or drag over things (and platforms) |
| P | 🏗️ Platform | Drag a rectangle to build a platform |

**More keys:**
- **Tab:** Toy Box
- **Space:** pause
- **G:** slow motion
- **F:** use the selected toy, or attack while playing as a fighter
- **Q / E:** rotate
- **R:** flip
- **N:** nail
- **Delete:** remove
- **Ctrl/Cmd+Z:** undo
- **H:** help

Move the camera with **WASD**, by dragging empty space, or by right-dragging. Scroll or pinch to zoom.

## Worlds and magic

**Worlds:**
- 🌼 Sunny Meadow
- 🧸 Toy Room
- 🍭 Candy Canyon (bouncy ground)
- ❄️ Frosty Peaks (slippery slopes)
- 🏝️ Splash Lagoon (sea and pier)
- 🌙 Moon Garden (low gravity, at night)
- ☁️ Cloud Kingdom (floating islands)
- 🏰 Battle Valley (two forts and two armies; press ⚔️ to start)
- 🧪 Acid Factory (catwalks, acid vats, conveyor, barrels)
- 🌋 Volcano (lava lake, and an erupting volcano that throws meteors)
- 🦕 Dino Valley (ferns and dinosaurs)
- 📐 Blank Canvas

**✨ Magic:** Party Time, Ball Rain, Big Wind, Rain Shower, Snow Day, Wobble Quake, Float Away, Rainbow Paint, Airstrike, Artillery, Meteor Shower and Heal Everyone.

**Gravity:** Normal, Moon, Zero-G, Upside Down and Heavy.

**🌙 Day/night:** lamps, saucers and fireworks glow in the dark.

**📒 Stickers:** 22 goals to earn, such as popping a Wiggly in two, winning a big battle, setting off a nuke, or putting a T-Rex in the playground.

## Play together

Everyone needs Wiggle Works on their own computer (Mac or Windows), on the **same Wi-Fi**. (This is for the 2D playground. For ⚔️ 3D Battle, use its own **👥** button: see the 3D Battle section.)

1. One person clicks **👥 Play Together → Host**. You can do this from the title screen or during a game, and you keep your current playground.
2. Friends click **👥 Play Together** and pick the host's playground from the list. They can also type the address the host's panel shows.
3. Everyone shares one playground. You'll see each other's cursors and names, what they're dragging, and who's playing as which Wiggly or fighter. Fighters, platforms and pits all show up for everyone. Say hi with emotes.

The host can untick **"Friends can change the world, clear everything and undo"** so nobody wipes the playground by accident.

The first time you host, your computer may ask whether to allow incoming network connections. Click **Allow**.

## For grown-ups and developers

### Run the tests

```bash
tools/run_tests.sh
```

The headless suites write their logs to `.test-logs/`:
- **core** covers the worlds, Wiggly jelly physics, split and merge, power, booms, freezing, undo, saves, and every toy, Wiggly special, magic spell and gravity setting.
- **fight** covers every fighter spawning and standing, giving weapons and armor, a red-vs-blue battle finding a winner, blasts throwing people (who then get back up), lava, platforms, personalities (defend, peaceful, coward), saving and loading, and the nuke.
- **battle** (3D Battle) covers spawning every fighter on every map, fights, explosions, getting up, chain reactions, mines and buildings, lava and acid, every mood, the nuke, every scenario, the HUD, and a 150-fighter speed check.
- **b3more** covers the 3D Battle extras: every Battle Rule (gravity, MEGA explosions, toughness, knockback, friendly fire, reinforcements, night, sunset, rain and snow), playing as a fighter (walking, jumping, shooting, stopping, getting knocked out), first person (the eye camera, mouse look, walking and shooting where you look, V back to overhead, jumping into a teammate when knocked out, and back overhead when nobody is left), screen shake, the follow camera, save slots, ⏮ Reset, and Surprise Battles reaching a winner with an MVP.
- **b3net** runs a 3D host and a friend on this computer (the friend in its own 3D world) and checks joining, seeing every fighter, building and pool in the same place, a friend placing a fighter, walking a soldier and driving a tank with their own keys, knock-outs, broken walls, effects, erasing, pausing and leaving.
- **vehicles** covers the race car, helicopter and fighter plane (spawning, the computer driving and fighting, being driven and flown in both views, staying inside the map, being shot down) and the network copies of every vehicle.
- **history** sets up every History battle (two sides, nobody falling or inside the ground, nothing moving before Fight!) and plays some out to a winner.
- **maps** loads every map, checks the ground right out to the edges, that fighters placed far out stand on it, the volcano's pools and the beach's water.
- **modes** goes from the title menu into 3D Battle and back, then into the 2D game. It checks that the physics settings the 3D mode changes are put back and that a 2D battle still plays out.
- **net** runs a host and a friend on this computer and checks joining, mirroring (including fighters and platforms), friend commands, the host's lock and snapshot size.
- **update** covers the updater without the internet: comparing versions, picking the right download, checking a download is whole (size and SHA-256), swapping the game file and putting it back if that fails, cleaning up old copies, and the update pop-ups.

`godot --headless --path . -- --test=update_live` asks GitHub for the newest release and downloads its Windows `.exe` the way **Update now** does. It needs the internet, so it isn't part of the suite.

`godot --headless --path . -- --test=perf` times an 80-fighter battle (`--b3=map [--fp]` times a 3D one). It isn't part of the suite.

### Build for other computers

```bash
tools/export_all.sh
```

This writes the Mac `.zip` and Windows `.exe` into `build/`. It needs Godot 4.7.2's export templates.

### Put out a new version

```bash
tools/release.sh 1.0.1 "New dinosaurs and fewer bugs"
```

This sets the version number, runs the tests, builds both apps, commits, tags `v1.0.1`, pushes to GitHub and makes a GitHub Release with `WiggleWorks-Windows.exe` and `WiggleWorks-Mac.zip`. Every Windows copy offers the update the next time it starts. Each version needs a bigger number than the last. Add `--skip-tests` to skip the 7-minute test run. It needs `gh` (the GitHub command-line tool) logged in.

### Regenerate the sounds and icon

```bash
python3 tools/gen_audio.py    # all the sound effects + the music loop (or name some: gen_audio.py honk)
python3 tools/gen_icon.py     # needs Pillow
```

Sounds and music are synthesized by the script, with no downloads or outside sound files.

### Screenshots

```bash
godot --path . -- --world=meadow --scenario=showcase --shot=shot.png
```

For 3D Battle:

```bash
godot --path . -- --battle3d --scenario=skirmish --shot=shot.png --shot-delay=10
```

Extra options: `--rules=time:night,weather:rain`, `--surprise=5` (a seeded Surprise Battle), `--history=ID` (a History battle; add `!` to start the fight, or use `lineup` to see all 14 soldiers), `--play` (play as a red fighter) or `--play=heli` (the first unit of that kind), `--fp` (first person), `--open=rules|saves|help|history`, `--map=beach`, and `--host3d` / `--join3d=IP` (share or join a battle).

3D scenarios: `skirmish`, `dinos`, `nuke`, `hazards`, `structures`, `animals`, `chaos`, `big` (150 fighters), `c4`, `vehicles`, `monsters`, `airshow` (6 planes and 4 helicopters over 60 fighters), `roadtrip` (cars and ramps), `hangar` (every vehicle up close). These don't fight: `lineup` and `closeup` (every model standing still), and `showcase`, `garage` and `firebreath` (close-ups). Use a delay of at least 8 seconds: the first few seconds go to compiling shaders.

`--open=toybox|worlds|magic|help|stickers|together|settings` opens a panel first. Use `--open=toybox:Dinos` to open a Toy Box tab. Battle scenarios: `battle`, `army`, `dinos`, `zoo`, `people` and `nukeit`.

### Layout

| Folder | What's in it |
|---|---|
| `autoload/` | `Catalog` (every Wiggly, toy, world, spell and sticker), `Settings` (name, color, sound, stickers), `Sfx` (sound and music), `Updater` (🔄 updates from GitHub Releases) |
| `game/` | `world.gd` (the playground and every command), `fighter.gd` (people and beasts: standing body, ragdoll, AI, weapons), `combat.gd` (bullets, blasts, hazards, who won), `wiggly.gd` (soft-body jelly), `toy.gd`, `toy_logic.gd` (what each toy does), `link.gd` (glue, hinge, rope, spring, wire), `builders.gd`, `worlds.gd`, `ground.gd`, `game.gd` (input and tools), `saves.gd` |
| `view/` | `art.gd` (all toy and Wiggly drawing), `fighter_art.gd` (people, animals, dinosaurs), `effects.gd` (particles, pops, lights, shake), backdrop, water/lava/acid, links, camera, previews |
| `ui/` | HUD, toy-box cards, title menu, Play Together panel, UI kit |
| `battle3d/` | 3D Battle: `battle3d.gd` (the mode, explosions, nuke, victory, ⏮ Reset), `b3_unit.gd` (fighter AI and combat), `b3_rig.gd` (3D models and animation), `b3_ragdoll.gd`, `b3_proj.gd` (arrows, rockets, bombs), `b3_struct.gd` (breakable buildings), `b3_hazard.gd`, `b3_fx.gd`, `b3_world.gd` (terrain, sky, trees), `b3_cam.gd`, `b3_tools.gd`, `b3_ui.gd`, `b3_scenarios.gd`, `b3_defs.gd` (all the data), `b3_rules.gd` (Battle Rules), `b3_player.gd` and `b3_ctl.gd` (playing a fighter or vehicle), `b3_fpview.gd` (the weapon in your hands in first person), `b3_vehicle.gd` / `b3_vrig.gd` (vehicles), `b3_aircraft.gd` (helicopter and plane), `b3_history.gd` (History battles), `b3_net.gd` (playing together), `b3_saves.gd`, `b3_surprise.gd`, `b3_weather.gd` |
| `net/` | Host, client, LAN discovery, snapshots |
| `tests/` | Headless test suites |
| `tools/` | `run_tests.sh`, `export_all.sh`, `release.sh` (new version on GitHub), and the sound and icon generators |
