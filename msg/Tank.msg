# uav_scout_bushfire/Tank
#
# What one vehicle is carrying, and where it is.
#
# The same message describes both fleets, because in this scenario they are
# the same kind of thing at different points in one supply chain:
#
#   dam  --->  scout tender  --->  drone  --->  fire
#
# Every link is finite and every link has to physically meet the next one. A
# drone holds about ten seconds of bombing; a tender holds about six drone
# loads; the dam is the only thing in the world that is inexhaustible, and it
# does not move.
#
# `x` and `y` are here rather than left to each vehicle's odometry on purpose.
# A thirsty drone has to be able to find a tender, and making it subscribe to
# every scout's odom to do that would put fleet composition into every node.
# The board carries the position of everything that has water.

string  vehicle    # namespace, e.g. uav_0 or scout_1
bool    tender     # true for a scout tender, false for a drone
float64 litres     # what it is carrying now
float64 capacity   # what it holds full
float64 x          # where it is, in the world frame
float64 y

# Tenders only. True when the scout is stopped and has water to give, which is
# the condition a drone needs before it commits to flying over there. A tender
# that is still driving is not a refuelling point: the drone would arrive to
# hover over a moving vehicle, which is the one manoeuvre this scenario cannot
# afford to get wrong.
bool    ready

# Tenders only: the one drone currently allowed to descend onto this vehicle,
# or empty for nobody.
#
# A tender serves one aircraft at a time, and this field is how the other two
# find out. Without it every thirsty drone flew to the tender's *centre* and
# station-kept there, so two or three of them held the same point at the same
# altitude - measured at 0.20 m apart with rotor tips 0.396 m out, which is not
# a near miss but a collision. Fires solved this long ago by giving each crew
# member a numbered station on a ring; a tender is the same problem with a
# queue instead of a crew, so it gets a served drone and a holding pattern.
string  serving
