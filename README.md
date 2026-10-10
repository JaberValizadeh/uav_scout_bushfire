# uav_scout_bushfire

Three **hector quadrotors** and two **AgileX Scout V2** ground robots fighting a
bushfire together, on ROS Noetic.

The drones bomb the fires. The scouts are the **water tenders**: a drone carries
about ten seconds of bombing and has to fly to a scout to reload, and a scout
has to drive to the dam to reload itself. Neither fleet can work the fire ground
alone.

```
dam  ->  scout tender  ->  drone  ->  fire
```

Every arrow is a physical rendezvous between two vehicles that had to get to the
same place, and every link but the first is finite.

They work a **20 x 20 m** stand of timber with a dam in the far corner.

```bash
source ~/uav_ws/src/uav_scout_bushfire/setup_coop.bash
roslaunch uav_scout_bushfire bushfire_coop.launch
```

`gui:=false` to run it headless, `rviz:=true` to watch the whole incident in one
view, `nav:=false` to drive the Scouts reactively instead of planning with
move_base.

RViz can also be run on its own, against an incident already flying:

```bash
roslaunch uav_scout_bushfire coop_rviz.launch
```

The drones take the **biggest fire first** and cannot leave one until it is out;
the Scouts **plan round both the timber and the fires**. Neither of those was
true of the first version — see [Choosing a fire](#choosing-a-fire-biggest-first)
and [Driving](#driving-move_base-and-the-fires-it-could-not-see).

> `setup_coop.bash`, not `setup_uav.bash`. This is the one package in `~/uav_ws`
> that needs `~/scout_ws` packages at **runtime** — `scout_description` is the
> robot, and `scout_gazebo` supplies both the `ros_control` configuration it is
> spawned with and the skid-steer node that turns `/cmd_vel` into four wheel
> velocities.

---

## What the cooperation actually is

[`uav_bushfire`](../uav_bushfire) is this package's parent, and in it water is
infinite: a drone descends onto a fire and bombs until the fire is out. Here the
tank runs out, and that one change is the whole scenario.

| | `uav_bushfire` | `uav_scout_bushfire` |
|---|---|---|
| what limits a drone | nothing but flying time | **40 litres**, ~10 s of bombing |
| a fire of 9 or 10 | one drone can finish it alone | needs a **crew or a refill** |
| running dry | cannot happen | normal — and is a *detour*, not a re-decision |
| ground robots | none | two tenders that drive water to the aircraft |
| what a scout must do | — | stand where the work is, and refill at the dam |

### The numbers, and why they are these numbers

Five parameters decide whether this is a scenario or three drones that never
need anybody:

| | | |
|---|---|---|
| `tank_capacity` | 40 L | a drone's load |
| `flow_rate` | 4 L/s | while bombing |
| `tender_capacity` | 240 L | six drone loads |
| `refill_rate` | 20 L/s | tender → drone, so two seconds a drone |
| `dam_rate` | 60 L/s | dam → tender |

40 L at 4 L/s is **ten seconds of bombing**. A fire costs `intensity × 1.2`
drone-seconds, so one tank finishes a fire of about **8.3 and no more** — every
9 and 10 on the board needs either a crew or a refill, which is the point. The
controller prints that arithmetic at startup, because it is the number that
decides whether the ground fleet matters:

```
[INCIDENT] one tank = 10.0 s of bombing = a fire of about 8.3;
           anything bigger needs a refill or a crew
```

The dam fills a tender three times faster than a tender fills a drone, on
purpose: the queue this scenario is meant to be about is the one at the tender,
not the one at the dam.

## How it works

```
                       ┌── /bushfire/hotspots ────> fire_suppressor ×3 ──/cmd_vel──> quadrotor
incident_controller ───┼── /bushfire/water ───────> water_tender ×2 ────/cmd_vel──> Scout V2
 (fires, crews,        │                    └─────> coop_monitor
  payouts, water)      └── /uav_N/bushfire/target
      ▲    ▲    ▲
      │    │    └──── /bushfire/claims ──── which fire each drone chose
      │    └───────── /bushfire/tenders ─── where each scout will stand
      └────────────── /uav_N/ground_truth/state, /scout_N/odom
```

| Node | Scope | Role |
|---|---|---|
| `incident_controller` | **global** | The fires, the crew register, the payouts — and the water ledger |
| `fire_suppressor` | per drone | Chooses fires, bombs them, and breaks off for water without giving up its claim |
| `water_tender` | per scout | Stands where the work is, dispenses, refills at the dam |
| `coop_monitor` | **global** | One screen showing the whole supply chain |

### Why the ledger owns the water

It could have lived in the vehicles — each one knows when it is bombing or
filling. It is central because **a transfer has two parties and one shared
quantity**, and the two parties are separate nodes: a drone that decided for
itself it had taken 40 litres and a tender that decided it had given 30 would
both be sincerely wrong and nothing would ever notice. Every transfer is written
as *the smallest of what the giver has, what the taker can hold, and what the
rate allows in `dt`*, so no amount of clock jitter can create or destroy water.

It also has to be there for a duller reason: the controller is already the thing
that computes, every tick, which drones are on station over which fire. Bombing
**is** the water consumption.

### The one line that makes this a cooperation

```python
on_station = [ns for ns in crew if self._on_station(ns, fire)]
working    = [ns for ns in on_station if self._litres[ns] > 0.0]
```

A dry drone on station over a fire is holding a perfect hover and achieving
nothing. Everything the scouts do exists to serve that line.

Note that `on_station` — not `working` — is what refreshes the commitment clock.
**A drone that is present and dry is waiting for water, not shirking**, and
timing it out would take a fire off an aircraft for doing exactly what the
scenario asks of it.

### Running dry is a detour, not a re-decision

A drone that empties mid-job **keeps its claim on the fire**, flies to a tender,
fills, and comes back to the same station. Releasing it instead would be wrong
twice: it would strand crewmates who sized the job on this drone being part of
it, and it would put the aircraft back into a market where the fire it just
spent a whole tank on looks no different from any other.

Before claiming anything *new*, though, a drone below `reserve_litres` (12 L)
tops up first. Arriving at somebody's fire with two seconds of water helps nobody
and spends a whole transit doing it.

### Where a tender stands

The board says which fires are burning and how many drones are on each. A fire
with a crew is a place where aircraft are spending water, so each scout scores
every crewed fire by

```
crew on it / (seconds to drive there + 2.0)
```

and parks at `standoff` (2.0 m) from the best one, **on the side facing the
middle of the arena**. Both parts matter: parked on the fire it would be under
the crew ring, where three aircraft descend to 0.95 m; offset towards the middle
keeps it out of the approach lane, since that is the side most drones arrive
from. The `+2.0` stops a fire the vehicle is already beside from scoring
infinitely and pinning it there while a bigger crew works elsewhere.

**Why it does not follow the thirstiest drone.** That was the obvious rule and
it is worse. A drone low on water is about to *leave* its fire, so chasing it
means driving towards a position it is in the act of vacating — and two tenders
chasing the same aircraft is that failure twice. Standing where the *work* is
means the tender is already in the right place when a drone runs dry, which is
the only moment its position matters.

Two tenders are kept apart the same way the drones are: each publishes the point
it intends to stand at on `/bushfire/tenders`, and one whose best option is
within `tender_separation` of a peer's claim takes its second choice. Nothing
accepts or refuses these — standing somewhere is not a resource that has to be
granted.

The **dam is the exception**, because there is one of it and both will need it.
That is solved by geometry instead: numbered docking slots on a ring, exactly
the answer a fire's crew stations are.

## Queueing at a tender

A tender is a **single point** and three drones want it. The first version let
them all fly to that point and station-keep on it, and the result was not a
near miss:

```
0.20 m   uav_1(CLIMB) / uav_2(REFILL)
0.25 m   uav_1(CLIMB) / uav_2(REFILL)
0.26 m   uav_0(TOWATER) / uav_2(CHASE)
```

Rotor tips are 0.396 m out, so contact happens below ~0.79 m. The worst case is
the one at the top: an aircraft climbing away full while the next descends into
the same column.

Fires solved this long ago with numbered crew stations. A tender is the same
problem with a **queue** instead of a crew, so it gets three things:

1. **One drone served at a time.** The tender nominates one (`Tank.serving`),
   sticky until that drone is full or leaves, with a 25 s safety timeout.
   Candidacy is horizontal proximity, **not** being in the refill altitude
   band — a drone only enters the band by descending and only descends once
   nominated, so band-based candidacy would mean nobody ever refuelled.
2. **Everyone else holds a ring** at `hold_radius` (2.0 m) at cruise, on a
   numbered slot: 3.46 m apart from each other and 1.05 m above whoever is
   being served. The bearing is a launch parameter, not something derived —
   deriving it from the namespace was tried, and `uav_0`/`uav_1`/`uav_2` differ
   by one character, so hashing them put the three holding points **3 cm
   apart**.
3. **A full drone clears sideways before the slot is handed on**, rather than
   climbing straight up out of the column the next one is descending into.

After: closest approach **0.62 m**, one pair of 396 inside contact range, and
no `REFILL` or `TOWATER` pair in the worst cases at all.

## Why the arena is 20 x 20

`uav_bushfire` runs on a 12 x 12 m stand, which is right for three aircraft
working alone. It is too small here, and the **ground fleet** is why: a Scout is
0.93 m long and drives at 1.1 m/s, so in a 12 m arena it is never more than a
few seconds from anywhere. The tenders were always already where they needed to
be, and the logistics half of the scenario cost nothing. There was also nowhere
to put the dam that was not either among the fires or on top of a launch point.

At 20 x 20 the numbers mean something. The dam at (8.5, 8.5) is a **12 m drive**
from the far side of the stand, so leaving for it at the wrong moment is a
decision with a cost, and a drone can be a 14 m transit from its next job —
more than one tank of water.

**Eighteen trees on three rings**, not eight. An arena three times the area with
the same eight trunks is open ground, and the reactive avoidance both fleets are
built around would never fire. `worlds/bushfire_big.world` is generated, and the
obstacle list the controller is given comes from the same numbers — a fire lit
inside a trunk is an aircraft grinding against bark until the reignite timer
moves it, and nothing checks.

Everything sized to the old arena moved with it:

| | 12 x 12 | 20 x 20 |
|---|---|---|
| fires lit within | ±4.0 | **±7.0** |
| fires burning | 5 | **7** |
| drone geofence, soft / hard | 4.8 / 8.0 | **8.8 / 12.5** |
| tender geofence | 5.4 | **9.4** |
| tender speed | 0.9 m/s | **1.1 m/s** |
| dam | (5.0, 5.0) | **(8.5, 8.5)** |
| commit timeout | 120 s | **180 s** |

## The Scout needed a sensor

The stock Scout V2 description carries **no sensors whatsoever** — it is a drive
base with four wheels and a deck. It has to cross a stand of trees that are in no
map it has, so this package adds a Hokuyo.

Where it goes is not obvious, and both mountings that look right are wrong:

| mounting | what breaks |
|---|---|
| low, under the deck — sees another Scout's chassis | the plane cuts through **this** vehicle's own wheels, and a reactive filter fed those returns believes it is permanently boxed in |
| on the deck at 0.34 m | the plane grazes the deck of every other Scout, so the two ground robots are barely visible to each other and move_base plans through the gap |

So the scanner goes on a **mast**, 0.265 m above `base_link` and about **0.50 m
above the ground**, with the full 270 degrees and 361 rays. That is high enough
to clear this vehicle's own body entirely, which is what lets the scan be used
raw.

It is too high to see another Scout's deck, though, and that is what the
**orange visibility pole** on each vehicle is for: a post rising through the
other's scan plane so each tender is a solid return rather than a hole in the
other's costmap. move_base plans straight through holes.

It still cannot see the drones, which is the right way round: they cruise at
2.0 m, and a ground robot that swerved for an aircraft two metres above it would
be a nuisance. The deconfliction between the fleets is vertical separation and
nothing else — sound only because the one place a drone comes low near a Scout
is the refill hover, directly over a tender that is **stopped**.

## Running two Scouts in one Gazebo

Namespacing a `ros_control` robot has three separate places it must be done, or
the second Scout silently drives the first one's wheels:

1. **`robot_description`** built with `robot_namespace:=$(arg ns)` — the
   `gazebo_ros_control` plugin inside the description reads it to find its
   controller manager.
2. **the controller yaml**, loaded inside the group, so the four velocity
   controllers are `/scout_0/scout_motor_*_controller`.
3. **the spawner**, run inside the group, so it talks to
   `/scout_0/controller_manager` rather than the global one — which, with two
   robots up, belongs to whoever started first.

`scout_gazebo`'s own launch does all of this in the global namespace, because it
was written to bring up exactly one robot.

The skid-steer node takes ground-truth odometry from `/gazebo/model_states`
rather than integrating the wheels. That matters more here than on a delivery
run: a skid-steer robot scrubs when it turns, wheel odometry cannot see the
scrub, and **this vehicle's whole job is to be at a known place** — the drones
fly at the position on the water board, and the ledger decides whether a refill
is happening from the same number.

## Driving: move_base, and the fires it could not see

The tenders plan with **move_base** over the shared map — global planner, local
planner, costmaps, recovery behaviours. `nav:=false` falls back to the built-in
reactive controller, which steers at the goal and swerves when something gets
close; it works, it just cannot route out of a concave pocket of timber.

### The one line that stopped any of it running

The navigation stack on this machine is a partial install. `move_base`,
`costmap_2d`, `amcl`, `gmapping`, `dwa_local_planner` and `map_server` are all
present; the **`global_planner` package is not**. The config named
`global_planner/GlobalPlanner`, and move_base loads its global planner as a
pluginlib plugin at startup — so naming a plugin from a package that is not
installed is not a warning and not a fallback. The node **exits 1 before it
writes a single log line**, and the tenders sit printing
`waiting for move_base...` forever with nothing to say why.

It is `navfn/NavfnROS` now, which is installed. For a 20 m arena of round trunks
the two are the same thing: grid Dijkstra/A* over the same costmap.

### Fire is invisible to the navigation stack

The flames are spawned with **no collision at all** — deliberately, so an
aircraft can fly down into one — which also means they return nothing to the
Hokuyo. The laser sees straight through a burning fire and the obstacle layer
marks nothing, so move_base plans across it because as far as the costmap is
concerned there is nothing there.

`water_tender` does carry its own fire avoidance, and turning the navigation
stack on **switched all of it off**. Its control loop hands over and returns
before any of it runs:

```python
if self._nav is not None:
    self._navigate(gx, gy)
    return
```

So `nav:=true` — the right thing for planning round timber — sent the tenders
straight back to driving through fires, and correctly so: nothing had told the
planner fires exist.

`scripts/fire_costmap` is the missing half. It turns the fire board into a
`PointCloud2` that the costmaps take as an observation source, so a fire is an
obstacle to the global planner exactly like a tree. Measured after: one tender
**never entered a fire keep-out** across 12,376 samples, the other was inside on
2.3% of samples, down from crossing them freely.

Two details in it are load-bearing:

**Marking only.** The obstacle layer clears by raytracing from the sensor origin
back through the cloud. That is right for a real sensor and actively wrong here:
this cloud's origin is the frame origin, so clearing would wipe every cell on
the line from the middle of the arena out to each fire — including trunks the
laser legitimately marked. Staleness is handled explicitly instead: when a fire
goes out or relights elsewhere, the node calls `clear_costmaps`.

**A filled disc, not a ring.** A ring leaves the cells inside a fire unmarked
and therefore cheaper than going round, and the planner will thread a path
straight through the middle, because that is the shortest route.

### Which fire rule applies to which driver

| | reactive | move_base |
|---|---|---|
| does not aim across a fire | `_fire_detour()` | the costmap |
| eases off near one | `_fire_speed_cap()` | — |
| backs out of one | `_drive_out_of_fire()` | `_drive_out_of_fire()` |

The escape runs in **both**, which is why it is tested before the handover
rather than after it. A fire can light on top of a tender standing exactly where
it should be, and that is not a steering failure — no detour fixes it, because
the vehicle is not going anywhere. Under move_base it also cancels the goal
first: driving out while the planner still steers toward a point inside the fire
is two controllers on one `/cmd_vel`, and whoever publishes last wins.

## The refill rendezvous

```
dist_xy <= refill_radius  AND  refill_min_altitude <= z <= refill_altitude
      (0.90 m)                      (0.45 m)              (1.30 m)
                        AND  the tender is stopped
```

The same shape as the suppression test, and the floor is load-bearing for the
same reason it is there: without it, a drone sitting on the ground beside a
tender refuels.

`ready` — stopped, with water — is judged **by the ledger, from the scout's own
odometry**, not taken on trust from the scout. The consequence of getting it
wrong is an aircraft descending onto a moving vehicle, and a drone will not set
off towards a tender that has not yet stopped.

## Arguments

| Arg | Default | Meaning |
|---|---|---|
| `gui` | `true` | Gazebo client. `false` is roughly twice as fast |
| `rviz` | `false` | RViz showing the fire ground and all five vehicles |
| `tank_capacity` | `40.0` | A drone's load, litres |
| `tender_capacity` | `240.0` | A scout's load, litres |
| `flow_rate` | `4.0` | Litres per second while bombing |
| `refill_rate` | `20.0` | Litres per second, tender to drone |
| `dam_rate` | `60.0` | Litres per second, dam to tender |
| `dam_x`, `dam_y` | `8.5`, `8.5` | Where the water is — out in the corner, on purpose |
| `dam_radius` | `2.00` | A tender this close to it is filling |
| `serve_radius` | `2.60` | A drone this close to a tender is in its queue |
| `hold_radius` | `2.00` | Where a drone waits its turn, on its own numbered bearing |
| `refill_radius` | `0.90` | How close a drone must hover to a tender |
| `refill_altitude` | `1.30` | …and no higher |
| `refill_min_altitude` | `0.45` | …nor lower, so a parked drone does not refuel |
| `reserve_litres` | `12.0` | Below this a drone tops up before bidding |
| `commit_timeout` | `180.0` | Long enough to cover a queue and a refill trip across 20 m |
| `num_hotspots` | `7` | Fires burning at once |
| `max_crew` | `3` | Most drones on one fire |
| `nav` | `true` | Plan with move_base. `false` uses the reactive controller |
| `collide` | `true` | Run `collision_monitor`; it only subscribes |
| `value_first` | `true` | Take the biggest fire, not the most efficient one |
| `fire_margin` | `0.60` | Added to a flame's radius to give the keep-out |
| `fire_caution` | `1.50` | Band beyond it where a tender eases off |
| `fire_creep_speed` | `0.30` | Speed inside that band, m/s |
| `fire_lookahead` | `4.0` | How far a candidate heading must stay clear of fire |
| `peer_radius` | `1.20` | Aircraft separation bubble |
| `peer_vsep` | `0.35` | …only when two are within this vertically |

Everything else — `collect_dist`, `work_per_intensity`, `join_deadline`, the
crew ring geometry, the flame model — is carried over from
[`uav_bushfire`](../uav_bushfire), where it is documented along with the six
bugs that produced it.

## Choosing a fire: biggest first

A fire's **intensity is both its value and its size**, and the value is split
equally between the drones that chose it — a 9 worked by three pays 3 each. That
mechanic comes from [`uav_bushfire`](../uav_bushfire); what is different here is
the ordering.

`_utility()` scores **share per second**, which is the efficient answer: it
sends a drone to a 3 next door rather than a 9 across the arena, because the 3
pays less but pays it much sooner. Efficient, and wrong for this scenario — the
9 is the fire that matters, and clearing cheap fires while it burns is exactly
what the scoring is meant to discourage.

So **intensity is the primary key**, and share-per-second only breaks ties
between fires of equal size. Measured: **10 of 10 taskings took the biggest
joinable fire**, with crews of two forming on the intensity-10s.

The gates in `_utility()` still apply and still return `None` — a full crew, or
a fire so near out that joining pays a full share for arriving after the work is
done — so "biggest first" fills the largest fire to `max_crew` and the fleet
then moves to the next largest. That is what "bigger fires may be worked by more
drones" means in practice. `value_first:=false` restores the efficiency
ordering.

**A drone cannot leave a fire it has chosen.** There are four paths that clear a
commitment and only one is voluntary: being respawned after an upset. The others
are the fire being out and paid, and the spotter reclaiming it after a tasking
timeout. Going for water keeps the fire — the excursion is a detour, not a
re-decision.

## Watching it: RViz

Either with the incident:

```bash
roslaunch uav_scout_bushfire bushfire_coop.launch rviz:=true
```

or on its own, in a second terminal, against one that is already running:

```bash
source ~/uav_ws/src/uav_scout_bushfire/setup_coop.bash
roslaunch uav_scout_bushfire coop_rviz.launch
```

The second form is the useful one while working on the view. Nothing in
`coop_rviz.launch` publishes to the scenario — it subscribes and draws — so it
can be started, killed and started again at any point in a run without
disturbing Gazebo, the planners or either fleet. The world is the slowest thing
to load and the thing you least want to restart.

`bushfire_coop.launch` includes that same file when `rviz:=true`, so there is
one definition of the view rather than two that drift.

The display worth knowing about is **Fire as obstacles** — the `fire_costmap`
cloud. It is what answers "why did a tender drive through that fire": if the
cloud is missing or in the wrong place, the planner is blind to fire again.
Alongside it are the shared map, the global costmap, each tender's live plan,
both fleets and the scouts' scans.

Two things had to be fixed before one window could show all of it.

**The fleets were on disconnected TF trees.** The aircraft publish under `world`
(Gazebo ground truth) and the Scouts under `map` (the navigation stack), and
nothing linked them — so RViz in `world` drew the drones and no scouts, and in
`map` the reverse, with the map, costmaps and plans visible in neither. The
frames do coincide: the map's `origin` places its frame on the arena centre,
where the world origin is. `rviz:=true` publishes the identity `world -> map`
rather than leaving it assumed. The residual difference is the scouts' odometry
drift, about 0.28 m after several minutes — which is what AMCL would correct if
this used it.

**The Scout would not render.** `planar_move` drives the body directly rather
than through wheel controllers, so nothing published joint states and the four
wheel links had no transform; `RobotModel` reports an error for links it cannot
place. Each Scout now runs a `joint_state_publisher`, which publishes the wheels
at rest — honest, since they are not simulated as turning either.

## Known limitations

**Nobody plans the supply chain.** Each tender greedily stands near the biggest
crew it can reach and each drone flies to the nearest ready tender. Nothing
anticipates: a tender does not set off for a fire it can see three drones
converging on, and no one schedules a dam trip for a lull. It works because the
fire ground is small, not because the policy is good.

**A tender that runs dry among the fires strands everybody.** `reserve_litres`
(45 L, about one drone load) is the only thing preventing it, and it is a fixed
threshold rather than a forecast — a scout that is asked for three refills in
quick succession can still be caught out.

**Collisions still happen, and the fixes for them are unproven.** Measured with
`scripts/collision_monitor`, all three kinds occur: drone-drone, drone-tree and
scout-scout. Two structural gaps were found and closed —

* the aircraft's `linear.y` was never filtered. Station-keeping over a fire is
  the one command that moves an aircraft sideways and it was published raw, so a
  drone could drift laterally into a trunk with avoidance engaged and unable to
  help. It matched the evidence: every drone-tree contact was a graze at station
  altitude, not a head-on strike in transit.
* the aircraft had **no positional awareness of each other at all**. The transit
  lanes (1.70 / 2.15 / 2.60 m) put each outside the others' horizontal scan
  plane, so they are mutually invisible except while crossing lanes — which is
  exactly the descent that puts two in the same place. They now share poses,
  with a vertical gate so ordinary lane crossings do not trigger it.

Both are sound in principle and **neither has been shown to reduce the collision
rate**. Before and after runs gave 0.83 and 1.37 contacts per minute, which is
the wrong direction; with 6 and 13 events the Poisson noise is about +-2.4 and
+-3.6, and fires ignite at random positions so the two runs are not the same
scenario. Settling it needs repeated fixed-seed runs with each change toggled.
That has not been done.

**A Scout cannot see a drone and a drone cannot see a Scout.** The scan planes
are 0.50 m and 2.0 m and the costmap's `max_obstacle_height` sits between them,
deliberately: a ground robot that braked for an aircraft two metres overhead
would be a nuisance. The one low-altitude encounter, the refill hover, is safe
because the tender is stopped and the drone station-keeps over it, but nothing
checks the airspace between.

**A fire can still light on top of a tender.** The escape gets it out, but the
deepest penetrations measured were all at 0.00-0.25 m/s against fires less than
a second old — a fire igniting onto a stationary vehicle, which no steering rule
can prevent.

**A drone that never turns up still gets paid.** Inherited from the parent: the
value of a fire is split between the drones that *chose* it, not the ones that
did the work.

## Files

| | |
|---|---|
| `launch/bushfire_coop.launch` | Gazebo, three aircraft, two scouts, the controller, optional RViz |
| `launch/one_uav.launch` | one aircraft's airframe + suppressor |
| `launch/one_scout.launch` | one Scout's airframe, `ros_control` stack, skid-steer and tender |
| `scripts/incident_controller` | fires, crews, payouts, the water ledger, the dam |
| `scripts/fire_suppressor` | the drone: choose, bomb, and go for water |
| `scripts/water_tender` | the scout: stand where the work is, dispense, refill, keep off the fire |
| `scripts/coop_monitor` | the whole supply chain on one screen |
| `scripts/fire_costmap` | the fire board as a costmap obstacle source, so move_base routes round fire |
| `scripts/collision_monitor` | measures drone-drone, drone-tree and scout-scout separations |
| `msg/Tank.msg` | one vehicle's load and position |
| `msg/WaterBoard.msg` | every tank plus the dam — what both fleets decide from |
| `msg/TenderClaim.msg` | a scout announcing where it will stand |
| `urdf/scout_v2_laser.urdf.xacro` | the Scout, with the sensor and drive it does not ship with |
| `worlds/bushfire_big.world` | the 20 x 20 m stand, 18 trees, generated |
| `maps/bushfire_big.*` | the same arena as an occupancy grid, shared by both Scouts |
| `config/move_base_params.yaml` | planners and recovery; **navfn**, see above |
| `config/costmap_common_params.yaml` | the laser and the fire cloud as observation sources |
| `launch/coop_rviz.launch` | RViz on its own, attachable to a running incident |
| `rviz/coop.rviz` | both fleets, the map, the costmap, the plans and the fires |
| `setup_coop.bash` | `setup_uav.bash` plus the Scout's meshes |

## Related packages

* [`uav_bushfire`](../uav_bushfire) — the same fire ground with drones only, and
  where the coalition mechanic, the flame model and most of the flying come from.
* [`uav_pick_place`](../uav_pick_place) — the same airframe with a gripper.
* `scout_mini_voice_control` — the Scout, flown by talking to it, in `~/scout_ws`.
