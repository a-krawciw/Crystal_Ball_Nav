#!/bin/bash

#############
# Description
#############

# This script is called from the ros1-ros2 foxy docker and does the following:
#
# 1) Read parameters including start time, filter etc
# 2) Start the ros nodes that we want:
#       > Localization
#       > Move Base
#           - Local planner
#           - Global Planner
#       > Deep SOGM predict
#       > (pointfilter, others ...)


############
# Parameters
############

# # Initial sourcing
source "/opt/ros/noetic/setup.bash"
source "nav_noetic_ws/devel/setup.bash"

# Printing the command used to call this file
myInvocation="$(printf %q "$BASH_SOURCE")$((($#)) && printf ' %q' "$@")"

# Init
XTERM=false     # -x
SOGM=false      # -s
TEB=false       # -b
MAPPING=2       # -m (arg)
GTSOGM=false    # -g
EXTRAPO=false   # -l
IGNORE=false    # -i

# Parse arguments
while getopts xsbm:gli option
do
case "${option}"
in
x) XTERM=true;;             # are we using TEB planner
s) SOGM=true;;              # are we using SOGMs
b) TEB=true;;               # are we using TEB planner
m) MAPPING=${OPTARG};;      # use gmapping, AMCL or PointSLAM? (respectively 0, 1, 2)
g) GTSOGM=true;;            # are we using loaded traj for GroundTruth predictions
l) EXTRAPO=true;;           # are we using loaded traj for linear interpolated SOGM
i) IGNORE=true;;            # are we igmoring dynamic obstacles
esac
done

echo ""
echo "Verify option incompatibility."
if [ "$GTSOGM" = true ] ; then
    if [ "$EXTRAPO" = true ] || [ "$IGNORE" = true ] ; then
        echo "ERROR: options -l -i and -o are incompatible."
        return
    fi
elif [ "$EXTRAPO" = true ] ; then
    if [ "$IGNORE" = true ] ; then
        echo "ERROR: options -l -i and -o are incompatible."
        return
    fi
fi
echo ""

if [ "$IGNORE" = true ] ; then
    SOGM=true
fi

# Wait until rosmaster has started 
until [[ -n "$rostopics" ]]
do
    rostopics="$(rostopic list)"
    sleep 0.5
done

# Wait for a message with the flow field (meaning the robot is loaded)
until [[ -n "$puppet_state_msg" ]]
do 
    sleep 0.5
    puppet_state_msg=$(rostopic echo -n 1 /puppet_state | grep "running")
done 

# Wait for a message with the pointclouds (meaning everything is ready)
until [[ -n "$velo_state_msg" ]]
do 
    sleep 0.5
    velo_state_msg=$(rostopic echo -n 1 /velodyne_points | grep "header")
done 

echo "OK"

# Get parameters from ROS
echo " "
echo " "
echo -e "\033[1;4;34mReading parameters from ros\033[0m"

rosparam set using_teb $TEB
rosparam set loc_method $MAPPING
rosparam set use_gt_sogm $GTSOGM
rosparam set extrapo_linear $EXTRAPO
rosparam set ignore_dynamic $IGNORE


GTCLASS=$(rosparam get gt_class)
c_method=$(rosparam get class_method)
TOUR=$(rosparam get tour_name)
t=$(rosparam get start_time)
FILTER=$(rosparam get filter_status)


echo " "
echo "START TIME: $t"
echo "TOUR: $TOUR"
echo "MAPPING: $MAPPING"
echo "FILTER: $FILTER"
echo "SOGM: $SOGM"
echo "GTCLASS: $GTCLASS"
echo "TEB: $TEB"
echo "GTSOGM: $GTSOGM"
echo "EXTRAPO: $EXTRAPO"
echo "IGNORE: $IGNORE"
echo " "


# Save Nav info to a log file
NAV_INFO_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/log_nav.txt"
echo "Navigation params" >> $NAV_INFO_FILE
echo "START TIME: $t" >> $NAV_INFO_FILE
echo "TOUR: $TOUR" >> $NAV_INFO_FILE
echo "MAPPING: $MAPPING" >> $NAV_INFO_FILE
echo "FILTER: $FILTER" >> $NAV_INFO_FILE
echo "SOGM: $SOGM" >> $NAV_INFO_FILE
echo "GTCLASS: $GTCLASS" >> $NAV_INFO_FILE
echo "TEB: $TEB" >> $NAV_INFO_FILE
echo "GTSOGM: $GTSOGM" >> $NAV_INFO_FILE
echo "EXTRAPO: $EXTRAPO" >> $NAV_INFO_FILE
echo "IGNORE: $IGNORE" >> $NAV_INFO_FILE

####################
# Start Localization
####################

echo " "
echo " "
echo -e "\033[1;4;34mStarting localization\033[0m"

# First get the chosen launch file
if [ "$MAPPING" = "0" ] ; then
    loc_launch="jackal_velodyne gmapping.launch"
elif [ "$MAPPING" = "1" ] ; then
    loc_launch="jackal_velodyne amcl.launch"
else
    loc_launch="point_slam simu_ptslam.launch filter:=$FILTER"
fi

# Add map path
loc_launch="$loc_launch init_map_path:=$PWD/../Data/Simulation_v2/slam_offline/2020-10-02-13-39-05/map_update_0001.ply"

# Start localization algo
if [ "$XTERM" = true ] ; then
    xterm -bg black -fg lightgray -xrm "xterm*allowTitleOps: false" -T "Localization" -n "Localization" -hold \
        -e roslaunch $loc_launch &
else
    NOHUP_LOC_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_loc.txt"
    nohup roslaunch $loc_launch > "$NOHUP_LOC_FILE" 2>&1 &
fi

# Start point cloud filtering if necessary
if [ "$FILTER" = true ]; then
    if [ "$MAPPING" = "0" ] || [ "$MAPPING" = "1" ]; then
        NOHUP_FILTER_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_filter.txt"
        nohup roslaunch jackal_velodyne pointcloud_filter2.launch gt_classify:=$GTCLASS > "$NOHUP_LOC_FILE" 2>&1 &
    fi
fi

echo "$loc_launch"
echo "OK"

# Waiting for pointslam initialization
echo ""
echo "Waiting for PointSlam initialization ..."
until [ -n "$map_topic" ] 
do 
    sleep 0.1
    map_topic=$(rostopic list -p | grep "/map")
done 
until [[ -n "$point_slam_msg" ]]
do 
    sleep 0.1
    point_slam_msg=$(rostopic echo -n 1 /map | grep "frame_id")
done

##################
# Start Navigation
##################

echo " "
echo " "
echo -e "\033[1;4;34mStarting navigation\033[0m"

# Chose parameters for global costmap
if [ "$MAPPING" = "0" ] ; then
    global_costmap_params="gmapping_costmap_params.yaml"
else
    if [ "$FILTER" = true ] ; then
        global_costmap_params="global_costmap_filtered_params.yaml"
    else
        global_costmap_params="global_costmap_params.yaml"
    fi
fi

# Chose parameters for local costmap
if [ "$FILTER" = true ] ; then
    local_costmap_params="local_costmap_filtered_params.yaml"
else
    local_costmap_params="local_costmap_params.yaml"
fi

# Chose parameters for local planner
if [ "$TEB" = true ] ; then
    if [ "$SOGM" = true ] || [ "$GTSOGM" = true ] || [ "$EXTRAPO" = true ] || [ "$IGNORE" = true ] ; then
        local_planner_params="teb_params_sogm.yaml"
    else
        local_planner_params="teb_params_normal.yaml"
    fi
else
    local_planner_params="base_local_planner_params.yaml"
fi

# Chose local planner algo
if [ "$TEB" = true ] ; then
    local_planner="teb_local_planner/TebLocalPlannerROS"
else
    local_planner="base_local_planner/TrajectoryPlannerROS"
fi

# Create launch command
nav_command="roslaunch jackal_velodyne navigation.launch"
nav_command="${nav_command} global_costmap_params:=$global_costmap_params"
nav_command="${nav_command} local_costmap_params:=$local_costmap_params"
nav_command="${nav_command} local_planner_params:=$local_planner_params"
nav_command="${nav_command} local_planner:=$local_planner"

# Start navigation algo
if [ "$XTERM" = true ] ; then
    xterm -bg black -fg lightgray -xrm "xterm*allowTitleOps: false" -T "Move base" -n "Move base" -hold \
        -e $nav_command &
else
    NOHUP_NAV_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_nav.txt"
    nohup $nav_command > "$NOHUP_NAV_FILE" 2>&1 &
fi

echo "OK"

######
# Rviz
######

RVIZ=false
if [ "$RVIZ" = true ] ; then
    t=$(rosparam get start_time)
    NOHUP_RVIZ_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_rviz.txt"
    nohup rviz -d nav_noetic_ws/src/jackal_velodyne/rviz/nav.rviz > "$NOHUP_RVIZ_FILE" 2>&1 &
fi


##################
# Run Deep Network
##################


if [ "$SOGM" = true ] ; then

    if [ "$IGNORE" = true ] ; then
        echo " "
        echo " "
        echo -e "\033[1;4;34mStarting with ignoring dynamic SOGM\033[0m"
    else
        echo " "
        echo " "
        echo -e "\033[1;4;34mStarting SOGM prediction\033[0m"
    fi
    

    t=$(rosparam get start_time)
    NOHUP_SOGM_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_sogm.txt"
    cd onboard_deep_sogm/scripts/
    nohup ./simu_collider.sh > "$NOHUP_SOGM_FILE" 2>&1 &
    cd ../../

    echo "OK"
    echo " "
    echo " "
        

else

    if [ "$GTSOGM" = true ] || [ "$EXTRAPO" = true ] ; then
    
        LOADWORLD=$(rosparam get load_world)
        LOADPATH=$(rosparam get load_path)
        if [ "$LOADWORLD" = "" ] || [ "$LOADWORLD" = "none" ] ; then
            echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
            echo "X  Error no world loaded that we can use for gt sogm  X"  
            echo "X  load_path = $LOADPATH                              X"
            echo "X  load_world = $LOADWORLD                            X"
            echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
        else

            if [ "$GTSOGM" = true ] ; then
                echo " "
                echo " "
                echo -e "\033[1;4;34mStarting with groundtruth SOGM\033[0m"
            
            elif [ "$EXTRAPO" = true ] ; then
                echo " "
                echo " "
                echo -e "\033[1;4;34mStarting with linear interp SOGM\033[0m"
            fi

            t=$(rosparam get start_time)
            NOHUP_GTSOGM_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_gtsogm.txt"
            nohup rosrun teb_local_planner gt_sogm.py > "$NOHUP_GTSOGM_FILE" 2>&1 &
                    
            echo "OK"
            echo " "
            echo " "

        fi
    fi
fi


##########################
# Run Deep Network Addenda
##########################


if [ "$SOGM" = true ] ; then

    echo " "
    echo " "
    echo -e "\033[1;4;34mStarting AER1516 Additions\033[0m"
    
    

    t=$(rosparam get start_time)
    NOHUP_AER_FILE="$PWD/../Data/Simulation_v2/simulated_runs/$t/logs-$t/nohup_aer1516.txt"
    cd onboard_deep_sogm/scripts
    nohup ./launch_aer.sh > "$NOHUP_AER_FILE" 2>&1 &
    cd ../../
    

    echo "OK"
    echo " "
    echo " "
           
fi

# Wait for eveyrthing to end before killing the docker container
velo_state_msg=$(timeout 10 rostopic echo -n 1 /velodyne_points | grep "header")
until [[ ! -n "$velo_state_msg" ]]
do 
    sleep 0.5
    velo_state_msg=$(timeout 10 rostopic echo -n 1 /velodyne_points | grep "header")
    echo "Recieved velodyne message, continue navigation"
    
    if [ "$IGNORE" = true ] ; then
        rosparam set /move_base/TebLocalPlannerROS/weight_predicted_costmap 0.0001
    fi
done 


echo "OK"
echo " "
echo " "
