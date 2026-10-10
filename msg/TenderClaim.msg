# uav_scout_bushfire/TenderClaim
#
# A scout announcing where it intends to stand. The ground fleet's equivalent
# of uav_bushfire/FireClaim, and it exists for the same reason: two vehicles
# deciding at the same time from the same picture will decide the same thing.
#
# It is weaker than a fire claim, though, and deliberately so. Nothing accepts
# or refuses this - there is no ledger of standing points, because standing
# somewhere is not a resource the way a slot in a crew is. It is published so
# the *other* scout can hear it and go somewhere else, and that is the whole
# protocol. A scout that hears a peer claim a point within ~tender_separation
# of its own best option simply takes its second choice.
#
# Which leaves one place where two tenders genuinely converge on the same
# ground: the dam. That is not solved here - it is solved by the dam having
# numbered docking slots, the same way a fire has numbered crew stations. See
# _dock() in incident_controller.

string  scout      # namespace of the scout, e.g. scout_0
float64 x          # the point it is driving to and will hold
float64 y
int32   fire_id    # the fire it is standing by, or -1 for the dam / no fire
