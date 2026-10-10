cmake_minimum_required(VERSION 3.0.2)
project(uav_scout_bushfire)

find_package(catkin REQUIRED COMPONENTS
  rospy
  std_msgs
  std_srvs
  geometry_msgs
  nav_msgs
  sensor_msgs
  tf
  gazebo_msgs
  visualization_msgs
  uav_bushfire
  message_generation
)

# Only the water messages are new. Hotspot, HotspotArray and FireClaim come
# from uav_bushfire - the fire ground is the same one, and two copies of a
# message set that has to agree is a bug waiting for a rebuild.
add_message_files(
  FILES
  Tank.msg
  WaterBoard.msg
  TenderClaim.msg
)

generate_messages(
  DEPENDENCIES
  std_msgs
)

catkin_package(
  CATKIN_DEPENDS rospy std_msgs std_srvs geometry_msgs nav_msgs sensor_msgs tf
                 gazebo_msgs visualization_msgs uav_bushfire message_runtime
)

catkin_install_python(PROGRAMS
  scripts/incident_controller
  scripts/fire_suppressor
  scripts/water_tender
  scripts/coop_monitor
  scripts/fire_costmap
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY launch urdf rviz config maps worlds
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
