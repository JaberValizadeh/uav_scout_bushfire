# uav_scout_bushfire/WaterBoard
#
# The whole supply chain in one message, published by incident_controller at
# the tick rate. It is to water what uav_bushfire's HotspotArray is to fires:
# the shared picture every vehicle makes its own decision from.
#
# A drone reads it to answer "am I dry, and which tender should I fly to".
# A scout reads it to answer "am I dry, and is anybody worth standing near".
# Neither asks anyone's permission - as with fire claims, the decision is local
# and only the ledger is central, because the ledger is the part that would
# race.
#
# The dam is on here rather than in a parameter each node reads separately so
# that there is exactly one authority on where the water comes from. Moving it
# is then a change in one place that the whole fleet sees on the next tick.

std_msgs/Header header

Tank[]  tanks       # every drone and every tender, with what it is carrying

float64 dam_x       # the standing water the tenders draw from
float64 dam_y
float64 dam_radius  # a tender this close to it is filling
