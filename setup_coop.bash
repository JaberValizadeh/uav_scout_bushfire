# Source this before launching uav_scout_bushfire.
#
#   source ~/uav_ws/src/uav_scout_bushfire/setup_coop.bash
#
# This is setup_uav.bash plus the one thing it deliberately leaves out. That
# script adds ~/scout_ws to the search paths for a single *executable* -
# scout_mini_voice_control's recognizer - and says so. This package needs more
# than an executable from over there: scout_description is the robot the
# tenders are, and scout_gazebo supplies both the ros_control configuration
# they are spawned with and the skid-steer node that turns /cmd_vel into four
# wheel velocities.
#
# The paths setup_uav.bash already exports cover all of that, because they are
# the same four variables for the same reasons - so this file is that one plus
# the model path Gazebo needs to resolve the Scout's meshes. Without the model
# path the robot spawns as an invisible collection of collision boxes and the
# only complaint is a mesh warning in the gzserver log.

source "$HOME/uav_ws/src/uav_pick_place/setup_uav.bash"

# package:// URIs in scout_description's URDF. hector's meshes are already on
# this path from setup_uav.bash; this appends rather than replaces, or the
# quadrotors lose theirs.
export GAZEBO_MODEL_PATH=$HOME/scout_ws/src/scout_ros:${GAZEBO_MODEL_PATH:-}

# ~/uav_ws is sourced last so that this workspace's own messages -
# uav_scout_bushfire/WaterBoard and friends - resolve ahead of anything with
# the same name that a second workspace might carry.
source "$HOME/uav_ws/devel/setup.bash" --extend
