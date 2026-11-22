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

When the game starts, it asks GitHub whether there's a newer version. If there is, **✨ New version!** pops up. **⬇️ Update now** downloads it, checks it arrived whole, swaps it in and restarts the game; **Later** skips it until next time. It only installs a file from this game's own GitHub releases whose SHA-256 fingerprint matches, and if the download stalls for 30 seconds it gives up and says so. **⚙️ Me → 🔄 Updates** has **Check for updates now** and a switch to stop checking when the game starts. The title screen shows the version in the bottom corner.

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

**Teams:** 🔴 Red, 🔵 Blue, 🟢 Green, 🟡 Yellow and 🐾 Wild. Wild beasts fight everyone. Teammates never hurt each other. If a battle goes 15 seconds with nobody getting hurt (say, two archers with a wall between them), everyone shouts **📣 CHARGE!** and runs straight at the enemy, so a battle never gets stuck.

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
4. Press **▶ Fight!** (Space). The team counts at the top right show who's left. The 🏁 Battle goal in ⚙️ Battle Rules decides who wins: the last team standing (the usual), whoever keeps their 👑 King safe, or whoever holds the 🚩 hill. 🏆

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
- **⇥ Tab (or N):** jump into the nearest teammate, in first person or overhead. Press it again for the next one, round and round. Teammates a friend is playing are skipped.
- **🖱️ Right-click powers:** every fighter, animal and dinosaur has one, and each needs a moment to recharge (vehicles use right-click for their second gun). The keys at the top of the screen show yours.
  - 🛡️ Knights, hoplites, legionaries, Saxons, Gauls and Immortals: hold to raise the shield. It blocks hits from the front and sides much better, but you walk slower.
  - 🎯 Sniper: in first person, right-click looks through the scope (right-click again to stop). Overhead, hold it for a steady aim with a red laser.
  - 🗡️ Redcoats, line infantry, Union and Confederate soldiers: a quick bayonet stab, even while reloading.
  - 🐂 Bulls, triceratops, mammoths and horsemen: charge where you aim (in first person, steer with the mouse).
  - 🦎 Raptor: pounce. 🐉 Dragon and 🦅 pterodactyl: swoop down and bite.
  - 💚 Medic: a healing pulse for teammates close by.
  - 🦍 Gorilla: ground pound up close, or throw a boulder somewhere far away.
  - 🦖 T-Rex roar and 🐘 elephant trumpet: push enemies back and stun them for a moment.
  - Everyone else: a kick (or a shove) that pushes an enemy back.
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
| 🏁 Battle goal | ⚔️ Last team standing; 👑 Defend the King (at Fight! each team gets a big crowned King with lots of health and a few guards; if your King falls, your team is out, even with others still standing); 🚩 King of the Hill (a glowing circle in the middle of the fighting, on a hill if there's one close by; a team scores while it's the only one in it, and the first to 100 wins). A panel at the top right shows the Kings' health or the score bars. |
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

**🎲 Surprise Battle:** builds a random battle and starts it a moment later. You get a random map, 2–4 equal armies (every army gets the same 🪙 points, priced like the puzzles: soldiers, knights and vikings, animals, dinosaur attacks, or total chaos), plus some cover, barrels, mines and maybe a lava pool.

**⏮ Reset:** when you press Fight!, the game remembers where everything was. **⏮** (next to Fight!) or **⏮ Play it again** on the winner screen puts every fighter, vehicle, building, barrel and pool back, ready to play the same battle again.

**💾 Save:** six save slots. Each keeps the whole battle: map, rules, fighters (with their team, mood, size and health), buildings, barrels, C4, mines and pools. Saving during or after a fight saves the setup from when you pressed Fight!, so loading it gives you the same battle to play again.

**📜 Pick a battle:** press **📜** in the top bar. The **📜 History** tab has real battles from long ago. Each one comes with a short, true story and what to watch for. It sets up both armies in their real formations, with the walls, stakes, earth forts, fences, beach obstacles and landing boats, then waits for you to press **Fight!** (or pick a soldier to play).

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

**🎯 Ready-made battles:** the **🎯 Ready-made** tab in the same pop-up has 15 battles to try: Skirmish, 🌊 Wave Defense, Dino Attack, Nuke!, Lava Bridge, Storm the Fort, Wild Animals, Total Chaos, Huge Battle (150 fighters), C4 Surprise, Tank Line, Monster Mash, Air Show, Road Trip and Hangar (every vehicle parked, ready to drive). **▶ Set it up** builds it on its own map and waits for **Fight!**. In Nuke! and C4 Surprise the boom comes once you press Fight!. Only the host can pick one when playing together.

**🧩 Army Puzzles:** the third tab in the 📜 pop-up. A blue army is already waiting, and you get some 🪙 points and your side of the map (the glowing area). Buy a red army from the Toy Box (each card shows its price; fighters are Normal size, and erasing before the fight gives the points back), then press ▶ Fight!. Win for ⭐, spend three quarters of the points or less for ⭐⭐, half or less for ⭐⭐⭐. Each win opens the next puzzle, and your stars are saved. If you lose, ⏮ Try again puts the blue army back and keeps yours so you can change it. Puzzle armies can't be erased, grabbed or changed, booms cost points and only go on your side, and if nobody is knocked out for a while the blue army charges. Solve them all for the 🧩 Puzzle Master sticker. Clearing, changing the map or picking another battle ends the puzzle. Only the host can start one.

| # | Puzzle | Map | Goal | 🪙 |
|---|---|---|---|---|
| 1 | 🧍 Stick Fight | Grassland | Beat 10 stick figures | 12 |
| 2 | 🏹 Arrow Rain | Farmland | Beat 10 archers behind sandbags | 10 |
| 3 | 🐺 Wolf Pack | Snow | Stop 8 hungry wolves | 18 |
| 4 | 🛡️ Shield Wall | Grassland | Break a shield wall of 5 knights | 16 |
| 5 | 🐉 Dragon Attack | Snow | A dragon and 6 vikings | 24 |
| 6 | 🗼 Tower Archers | Farmland | Knock out the archers in the towers | 24 |
| 7 | ⛰️ Hold the Pass | Mountain Pass | 12 vikings | 28 |
| 8 | 🦏 Dino Stampede | Grassland | 2 triceratops and 4 raptors | 30 |
| 9 | 🏘️ Town Square | Town | 8 soldiers and 2 MG turrets | 30 |
| 10 | 🌉 Hold the Bridge | Volcano | 21 wild vikings at a bridge over lava | 30 |
| 11 | 🪖 Tank Trouble | Desert | Stop 3 tanks | 36 |
| 12 | 🦖 T-Rex! | Farmland | A T-Rex and 4 raptors | 36 |
| 13 | 🏖️ Storm the Beach | Beach | An MG turret, soldiers and a sniper by 2 bunkers on the hill | 48 |
| 14 | 🌋 The Big One | Volcano | Vikings, a giant, a robot, a tank, a T-Rex and archers | 76 |

**⭐ History stars:** each History battle has three: ⭐ Finish it (someone wins), ⭐ Change history (the side that lost long ago wins) and ⭐ Hero (your side wins while you play in first person). The cards show the ones you have.

**🌊 Wave Defense:** hold the fort against wave after wave! Pick 🌊 Wave Defense in 📜 → 🎯 Ready-made. You get a fort (sandbags round a tower and a bunker, with a few defenders) and 🪙 points to spend in the glowing area: fighters, vehicles like the MG turret and cannon, walls, sandbags, towers, mines and boom barrels. Press ▶ Fight! (or ▶ Start wave 1) and the blue attackers march in from the far side. Every attacker you knock out is worth 🪙 1 (a boss 🪙 10), and holding the fort earns a bonus. Between waves there's a short break to buy more; press ▶ Next wave (or Enter) if you can't wait. The waves get stronger: stick figures and soldiers, then vikings and knights, cavalry and raptors, dinosaurs, then tanks and air raids, with a HUGE boss every 5th wave (a giant, a T-Rex, a dragon…). The fort falls when nothing of yours is left in it. The panel at the top right shows the wave, how many attackers are left and your ⭐ best wave. Pick a defender and press 🎮 Play as me! to fight alongside your army, in first person too. ⏮ Play it again starts from wave 1 with the fort you had.

**🏆 Scoreboard:** when a battle ends, a card under the winner banner shows how long it took, how many fighters each team brought and still has, the knock-outs each team scored (and those by booms, lava and falls), and the top 3 fighters 🥇🥈🥉, even ones that were knocked out. Friends playing together see it too. The fighter with the most knock-outs is also named ⭐ MVP.

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
| Tab | Hide or show the Toy Box. While playing: jump into the next teammate |
| N | While playing: jump into the next teammate |
| Right-click | While playing: your fighter's power (shield, scope, charge, kick…) |
| P | Play as the selected fighter or vehicle (Esc stops) |
| Enter | 🌊 Wave Defense: ▶ Next wave |
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
- Friends see the battle goal too: the Kings' crowns and health, the glowing hill and its scores, the wave, the countdown and the 🪙 points. In Wave Defense they can buy defenders in the fort (from the host's points) and press ▶ Next wave.
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

**Wigglies vs fighters:** ⚡ Zappy's zap stuns people, animals and dinosaurs for a moment and jumps from one to the next (wet fighters and ones in metal armor get it worse, and it runs right through a pond full of soldiers). 🔥 Blaze sets them on fire (a wet one just steams) and melts frozen ones out. 🩵 Frosty (and the ❄️ Freeze Bomb) freezes them into ice blocks, even a charging bull or a soldier in mid-jump; the ice pops after a few seconds, or a big hit smashes it sooner. ⚪ Boulder's Ground Pound launches squads standing nearby. 🟢 Gummy in Sticky Mode sticks to a T-Rex or bull that bumps into it and slows it right down until it shakes Gummy off. A big or fast Wiggly bowls people over; small slow ones roll past.

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
- **Toys vs fighters:** the 🛸 saucer's tractor beam lifts fighters and dinos (big ones slowly). Fans and ✨ Big Wind blow fighters back (chickens tumble away, a T-Rex barely budges) and can blow them off platforms. The Bubble Maker floats people and small animals away in bubbles, and a Bubble Bomb catches everyone nearby, even a T-Rex; when the bubble pops they tumble down and get back up. Magnets drag fighters in metal armor over and yank metal weapons (swords, axes, hammers, guns, the bazooka) out of their hands; bows, spears, clubs and laser swords stay put. A Glue Bomb gums up everyone's feet. Heavy, fast things knock fighters over: bowling and steel balls, thrown blocks, catapult shots, bodies thrown by blasts, and a go-kart or monster truck that's driving. It mostly knocks them down and only hurts a bit. 💧 Water and 🌧️ Rain Shower make fighters wet: fire goes out (napalm too), but zaps hurt more. Click a fighter to see 🧊 frozen, 🫧 in a bubble, ⚡ zapped, 🍬 sticky, 💧 wet or 🔥 on fire next to its health.
- **🔌 Battle traps:** wire a battery, switch, Big Button or Blinky Timer to a boom (C4, dynamite, landmine, barrels, grenade, cluster bomb, napalm, acid bomb, nuke, firework, the bubble/paint/glue/freeze bombs, mega boom, confetti popper) and power sets it off. A Big Button is a pressure plate, even nailed down. A Zappy zap sets booms off too.

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

**📒 Stickers:** 28 goals to earn, such as popping a Wiggly in two, winning a big battle, setting off a nuke, or putting a T-Rex in the playground. 3D Battle has its own: 🏆 Victory!, ✈️ Ace Pilot (3 knock-outs while flying), 🧨 Tank Buster, 📜 History Buff (finish 3 different History battles) 👀 First-Person Hero (win while playing in first person) and 🧩 Puzzle Master (solve every Army Puzzle). It also gives General, Hero, Big Bada Boom and Boom Boom Boom.

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
tools/run_tests.sh               # every suite (about 8 minutes)
tools/run_tests.sh b3more net    # just these
```

A suite fails if it exits with an error, prints a SCRIPT ERROR or a parse error, or never prints its summary. The logs go to `.test-logs/`:
- **core** covers the worlds, Wiggly jelly physics, split and merge, power, booms, freezing, undo, saves, and every toy, Wiggly special, magic spell and gravity setting. It also checks world pieces surviving Clear, glue and hinges holding, dragging while paused, lava not floating things, and animated toys moving.
- **toyfight** covers toys and Wiggly powers against fighters: zaps (chains, wet and metal), fire, water and rain, ice (thawing, smashing), ground pound, Gummy and glue, big Wigglies, the saucer beam, fans, bubbles, magnets (weapons yanked loose), wired traps and pressure plates, heavy things bowling armies over, how a friend's screen shows it, and a 100-fighter speed check.
- **fight** covers every fighter spawning and standing, giving weapons and armor, a red-vs-blue battle finding a winner, blasts throwing people (who then get back up), lava, platforms, personalities (defend, peaceful, coward), saving and loading, and the nuke. It also checks Revive healing one fighter, armor not stacking, paused swings, gunners reloading, no spinning ragdoll limbs, held weapons, two shooters with a wall between them not just standing there, and 📣 CHARGE! ending a stand-off.
- **battle** (3D Battle) covers spawning every fighter on every map, fights, explosions, getting up, chain reactions, mines and buildings, lava and acid, every mood, the nuke, every scenario, the HUD, and a 150-fighter speed check. It also checks no jumping in mid-air, melee reach (no healing hits, nothing far overhead), hazard and burn damage following the rules, shots flying past teammates, projectiles following the Gravity rule, and the effects pool.
- **b3menu** covers the 📜 pop-up's 🎯 Ready-made tab (every battle sets up on its map and waits for Fight!; nuke and C4 go off after Fight!), the 🏆 scoreboard (numbers, top 3, keeping up after the win, a friend's copy, made-up lines ignored), the 3D stickers, and the title screen's Sticker Book fitting and scrolling.
- **b3powers** covers the right-click powers (which fighter gets which, what each does, cooldowns, friends' powers) and ⇥ Tab jumping to the next teammate.
- **b3puzzle** covers 🧩 Army Puzzles and the 🪙 points: prices, your side only, refunds, ⏮ Reset, clearing, the glowing area, the tab and its locks, setting up, keeping the blue army as it is, booms costing points, every puzzle won by a test army with its stars saved, trying again, leaving a puzzle, History stars, fair Surprise armies and saving the stars.
- **b3modes** covers the 🏁 battle goals (Kings crowned, guarded and falling, the hill scoring only while one team holds it alone, fighters heading for it, the winner banner, scoreboard and ⏮ Reset) and 🌊 Wave Defense (the fort and points, buying in the fort, waves coming and getting stronger, points for knock-outs, the break and ▶ Next wave, losing, the best wave being saved, playing in first person, the panel's place on the screen).
- **b3more** covers the 3D Battle extras: every Battle Rule (gravity, MEGA explosions, toughness, knockback, friendly fire, reinforcements, night, sunset, rain and snow), playing as a fighter (walking, jumping, shooting, stopping, getting knocked out), first person (the eye camera, mouse look, walking and shooting where you look, V back to overhead, jumping into a teammate when knocked out, and back overhead when nobody is left), screen shake, the follow camera, save slots, ⏮ Reset, and Surprise Battles reaching a winner with an MVP. It also checks the History tab's team picker, placement previews after playing, the first-person hit marker and body, saves keeping heights and History strength, Surprise Battle spacing, the top bar fitting, and your own shots landing in Moon gravity.
- **b3net** runs a 3D host and a friend on this computer (the friend in its own 3D world) and checks joining, seeing every fighter, building and pool in the same place, a friend placing a fighter, walking a soldier and driving a tank with their own keys, knock-outs, broken walls, effects, erasing, pausing and leaving. It also checks a friend's raised shield and Tab, the 🏁 battle goal and 🌊 Wave Defense on a friend's screen (crowns, the hill and its scores, the wave and countdown, the 🪙 points, a friend buying in the fort), trees knocked down before joining, vehicles facing the same way, airstrike planes, the nuke's flash, junk packets and effect names being ignored, and spam limits.
- **vehicles** covers the race car, helicopter and fighter plane (spawning, the computer driving and fighting, being driven and flown in both views, staying inside the map, being shot down) and the network copies of every vehicle. It also checks planes shot down at the map edge, guns firing past teammates, and bombs in Moon gravity.
- **history** sets up every History battle (two sides, nobody falling or inside the ground, nothing moving before Fight!) and plays some out to a winner.
- **maps** loads every map, checks the ground right out to the edges, that fighters placed far out stand on it, the volcano's pools and the beach's water. It also checks that knocked-over rocks keep their color.
- **modes** goes from the title menu into 3D Battle and back, then into the 2D game. It checks that the physics settings the 3D mode changes are put back and that a 2D battle still plays out. It also checks the separate sound and music volumes, the full-length music loop and saving sticker progress.
- **net** runs a host and a friend on this computer and checks joining, mirroring (including fighters and platforms), friend commands, the host's lock and snapshot size. It also checks for leftover copies on a friend's screen, fighter health and weapons syncing, junk packets and spam limits.
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

This sets the version number, runs the tests, builds both apps, commits the new version number, tags `v1.0.1`, pushes to GitHub and makes a GitHub Release with `WiggleWorks-Windows.exe`, `WiggleWorks-Mac.zip` and `SHA256SUMS.txt`. Every Windows copy offers the update the next time it starts. Each version needs a bigger number than the last. Add `--skip-tests` to skip the test run.

Before it changes anything, it checks that `gh` (the GitHub command-line tool) is logged in and that everything else is already committed, so commit your changes first.

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

2D scenarios `vs_powers`, `vs_machines` and `vs_traps` (with `--world=canvas`) show Wigglies and toys against fighters.

For 3D Battle:

```bash
godot --path . -- --battle3d --scenario=skirmish --shot=shot.png --shot-delay=10
```

Extra options: `--rules=time:night,weather:rain`, `--surprise=5` (a seeded Surprise Battle), `--history=ID` (a History battle; add `!` to start the fight, or use `lineup` to see all 14 soldiers), `--play` (play as a red fighter) or `--play=heli` (the first unit of that kind), `--fp` (first person), `--open=rules|saves|help|history|ready|puzzles`, `--open=puzzle:ID` (set one up) or `--open=puzzle:ID:win` (set it up and win it), `--map=beach`, and `--host3d` / `--join3d=IP` (share or join a battle).

3D scenarios: `skirmish`, `dinos`, `nuke`, `hazards`, `structures`, `animals`, `chaos`, `big` (150 fighters), `c4`, `vehicles`, `monsters`, `airshow` (6 planes and 4 helicopters over 60 fighters), `roadtrip` (cars and ramps), `hangar` (every vehicle up close), `waves` (🌊 Wave Defense; `waves:7` starts at wave 7, `waves:0` waits for Fight!). Add `--rules=goal:king` or `goal:hill` for the other battle goals. These don't fight: `lineup` and `closeup` (every model standing still), and `showcase`, `garage` and `firebreath` (close-ups). Use a delay of at least 8 seconds: the first few seconds go to compiling shaders.

`--open=toybox|worlds|magic|help|stickers|together|settings` opens a panel first. Use `--open=toybox:Dinos` to open a Toy Box tab. Battle scenarios: `battle`, `army`, `dinos`, `zoo`, `people` and `nukeit`.

### Layout

| Folder | What's in it |
|---|---|
| `autoload/` | `Catalog` (every Wiggly, toy, world, spell and sticker), `Settings` (name, color, sound, stickers), `Sfx` (sound and music), `Updater` (🔄 updates from GitHub Releases) |
| `game/` | `world.gd` (the playground and every command), `fighter.gd` (people and beasts: standing body, ragdoll, AI, weapons), `combat.gd` (bullets, blasts, hazards, who won), `wiggly.gd` (soft-body jelly), `toy.gd`, `toy_logic.gd` (what each toy does), `link.gd` (glue, hinge, rope, spring, wire), `builders.gd`, `worlds.gd`, `ground.gd`, `game.gd` (input and tools), `saves.gd` |
| `view/` | `art.gd` (all toy and Wiggly drawing), `fighter_art.gd` (people, animals, dinosaurs), `effects.gd` (particles, pops, lights, shake), backdrop, water/lava/acid, links, camera, previews |
| `ui/` | HUD, toy-box cards, title menu, Play Together panel, UI kit |
| `battle3d/` | 3D Battle: `battle3d.gd` (the mode, explosions, nuke, victory, ⏮ Reset), `b3_unit.gd` (fighter AI and combat), `b3_rig.gd` (3D models and animation), `b3_ragdoll.gd`, `b3_proj.gd` (arrows, rockets, bombs), `b3_struct.gd` (breakable buildings), `b3_hazard.gd`, `b3_fx.gd`, `b3_world.gd` (terrain, sky, trees), `b3_cam.gd`, `b3_tools.gd`, `b3_ui.gd`, `b3_scenarios.gd`, `b3_defs.gd` (all the data), `b3_rules.gd` (Battle Rules), `b3_player.gd` and `b3_ctl.gd` (playing a fighter or vehicle), `b3_fpview.gd` (the weapon in your hands in first person), `b3_vehicle.gd` / `b3_vrig.gd` (vehicles), `b3_aircraft.gd` (helicopter and plane), `b3_history.gd` (History battles), `b3_puzzles.gd` (🧩 Army Puzzles and the glowing build area), `b3_modes.gd` (🏁 battle goals and 🌊 Wave Defense), `b3_mode_hud.gd` (their panel), `b3_net.gd` (playing together), `b3_saves.gd`, `b3_surprise.gd`, `b3_weather.gd` |
| `net/` | Host, client, LAN discovery, snapshots |
| `tests/` | Headless test suites |
| `tools/` | `run_tests.sh`, `export_all.sh`, `release.sh` (new version on GitHub), and the sound and icon generators |
