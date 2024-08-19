# Fighting RPG

Blend a fighting game with an MMORPG by having players learn new moves when they level up. Wuxia theme seems like a good fit. Dynamically animated 2D-bones anime-esque art style seems like a good fit (see animelee clips).

## Technical Architecture

Zig front-end client talking to zig-server over raw udp. The server will make peer-to-peer matches between players who want to fight, which will be UDP, rollback netcode, direct connection fights. There's gotta be some ping-limiter from the webserver's end to prevent bad connection fights.

I should be able to just straight up use the [GGPO lib](https://github.com/pond3r/ggpo/blob/master/doc/DeveloperGuide.md) in zig

In the Overworld, the client is using "rollback-style" connection with the server as the "opponent." However, the server is only giving the client the inputs that would "affect" them, since the client is only rendering the local area around the player.

[zig udp server](https://blog.reilly.dev/creating-udp-server-from-scratch-in-zig)

#### client

First, open connection to server and login.

Second, render "character-local game-state."

On user input, simulate the world advancing, and send input to server.

On "nearby" other-user input, the server sends an input+state-update to the client

Keeps a subset of full game-world state in-memory. Keeps a connection to the server open. Forwards input along the connection to the server, and optimistically renders. Gets other-players inputs from server and renders them. Gets periodic local-state refreshes to keep client view in-sync with server.

Over-world mode => rollback connection to server
AI-fight mode => no connection, only client-local simulation
Player-fight mode => rollback connection to opponent

To start a fight, all involved clients send a notification to the server, so it can indicate that a fight is taking place at some location.
After a fight, all involved clients send fight results to the server. Disagreement resolution occurs, and the server updates its state, which propagates to clients eventually.

#### server

Needs same game-simulation logic as client, but does not need any rendering logic.

Full game-world state is held in-memory. UDP connections to all clients are simeltaneously held open.

## Design Ideas

### Character creation

First choose species:
Human, Rat, Ox, Tiger, Rabbit, Dragon, Snake, Horse, Sheep, Monkey, Rooster, Dog, Pig

Then choose gender.

If human, choose body type: kid, classic, fat, bodybuilder

### Moves

Melee-inspired control scheme:

- Direction (little/full sensitivity)
- attack button (A)
- qi attack button (B)
- defense button (y)
- jump button (x)

Together these inputs produce the following move slots:

- little left: walk left
- little right: walk right
- full left: run left
- full right: run right
- any down: crouch
- jump button: jump (the longer you press it, the higher you jump, linearly by frame until the max jump)

- neutral + attack button
- little forward + attack button
- little up + attack button
- little down + attack button
- full forward + attack button
- full up + attack button
- full down + attack button

- neutral + qi attack
- little forward + qi attack
- little up + qi attack
- little down + qi attack
- full forward + qi attack
- full up + qi attack
- full down + qi attack

- in air + neutral direction + attack button
- in air + forward + attack button
- in air + backward + attack button
- in air + up + attack button
- in air + down + attack button

- neutral + defense button
- left + defense button
- right + defense button
- down + defense button
- qi + defense button
- landing + defense button (l-cancel)
- in air + neutral + defense button
- in air + left + defense button
- in air + right + defense button
- in air + down + defense button

Progression:

every character starts with:

1. walk
2. run
3. crouch
4. jump
5. jab (grounded + no direction + attack button)
6. forward block (grounded + no direction + defense button)
7. fAir (in air + forward + attack button)

and a full character will have

1. walk
2. run
3. crouch
4. jump xN (depending how much you invest in getting more jumps)
5. block, roll, dodge, qi sheild, l-cancel, directional air dodge
6. jab (grounded + no direction + attack button)
7. 3 grounded directional tilt attacks
8. 3 grounded directional smash attacks
9. 5 aerial attacks
10. neutral qi move
11. 3 tilt qi moves
12. 3 smash qi moves

Controller:

Keyboard:

### Progression

Chinese magic number is 4. Thus, we have 4 "Realms" of 4 "Stages" of 4 "levels." Realms and Stages are named, but levels are just numbered. So you start off at "Earthly Realm, Dirt Stage, Level 1"

Realms with their stages:

- Earthly Realm
  - dirt
  - clay
  - wood
  - stone
- Metallic Realm
  - copper
  - bronze
  - iron
  - steel
- Precious Realm
  - jade
  - silver
  - gold
  - diamond
- Heavenly Realm
  - cloud
  - moon
  - sun
  - star

To advance a level, cultivate more chi. You can get it from meditating (mini-game?) or from chi crystals.

There are certain places in the world (mountain peaks, waterfalls, caves, etc) where chi is abundant, and you can meditate there to gain chi. Too many players in the same spot will quickly dissipate the chi and it will take a while to naturally reform.

When you kill something, they drop chi crystals. You can consume chi crystals to increase your stored chi. (mini-game?) However since chi-crystals are good for advancement, they are also effectively money.

Weak monsters drop low chi, strong monsters drop high chi. You need more chi to advance the further up you are, but ln(x) more, not exponentially more.

### random ideas

- for each chi move you learn, your soul gets slightly aspected towards that type of chi (like fire/water/etc). Thus it is easier to learn more moves of that type, and harder to learn moves of other types. This might be too much complexity, but, imagine a mini-game which essentially gives a reaction window for learning a move which increases or decreases based on your soul affinity. And make each attempt to learn a move cost something. (probably chi?)
- (i like) collect chi from killing monsters
- (nah) cultivate chi to expand your dantian or to attempt to ascend to the next level
- each level up your character gains one open move slot and some stats
- find manuals or try to invent your own moves to fill your character's move slots
- some moves require weapons
- alchemy to create pills requires combining rare ingredients. the game mechanic is hex color addition. Each ingredient has it's own color, and quantity. The more other ingredients there are already in the pot, the less adding your next ingredient will move the color toward the ingredient's color. Additionally, temperature must be controlled, and if it is too hot, the color drifts up and if it is too cold, the color drifts down, more rapidly the more distant temperature is from where it should be. Each recipie for a pill requires getting a pot to a certain color range and holding it there for a certain amount of time. More complex pills may require multiple stages, like get to blue, hold for a while, get to red, hold for a while, etc, which represents an ideal "color path" of correct color over time. The area under the curve difference between the ideal color path and the actual color path taken determines the quality of the pill(s) produced. The quantity of ingredients used determines how many pills are created at once. This system means that multiple ingredient combinations can be used to produce the same pill

### View Modes

Two main "views":

1. overworld pokemon-esque tile walk-about and interact, probably sprite-based?
2. in-fight melee-esque platform-fighter. No sprites, actual animated bones on character models
