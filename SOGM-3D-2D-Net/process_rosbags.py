#
#
#      0==============================0
#      |    Deep Collision Checker    |
#      0==============================0
#
#
# ----------------------------------------------------------------------------------------------------------------------
#
#      Callable script to process data from rosbags
#
# ----------------------------------------------------------------------------------------------------------------------
#
#      Hugues THOMAS - 06/03/2020
#


# ----------------------------------------------------------------------------------------------------------------------
#
#           Imports and global variables
#       \**********************************/
#

# Common libs
import numpy as np
import sys
import os
from os import listdir, makedirs
from os.path import join, exists
import time as RealTime
import pickle
import json
import subprocess
import rosbag
import plyfile as ply
import shutil
from utils import bag_tools as bt

from utils.ply import write_ply


# ----------------------------------------------------------------------------------------------------------------------
#
#           Utilities
#       \***************/
#


# ----------------------------------------------------------------------------------------------------------------------
#
#           Main Call
#       \***************/
#


def main(save_velo=True,
         save_classif=False,
         save_collider=False,
         save_traj=True):

    # Result folder
    run_path = '../Data/Real/runs'
    if not exists(run_path):
        makedirs(run_path)

    # Path to the bag files
    bags_path = '../Data/Real/rosbags'

    # List all bag files in folder
    bag_files = np.sort([f for f in listdir(bags_path) if f.endswith('.bag')])
    bag_dates = [f[:-4] for f in bag_files]

    for i, file in enumerate(bag_files):

        ######
        # Init
        ######

        # Start Time
        start_time = 0

        # Read the bag file
        file_path = join(bags_path, file)
        bag = rosbag.Bag(file_path)

        # Create a result folder for it
        res_path = join(run_path, bag_dates[i])
        if not exists(res_path):
            makedirs(res_path)
            
        print("\nReading", file_path)
        print("*" * (len(file_path) + 8))
        print()

        ##############
        # Lidar frames
        ##############

        if save_velo:

            # read in lidar frames
            t1 = RealTime.time()
            print("Reading lidar frames")
            frames = bt.read_pointcloud_frames("/velodyne_points", bag)

            if len(frames):
                if not exists(join(res_path, 'velodyne_frames')):
                    makedirs(join(res_path, 'velodyne_frames'))

            # write lidar frames to .ply files
            for timestamp, data in frames:

                # Get timestamp
                frame_time = timestamp.to_sec()
                frame_name = "{:.6f}.ply".format(frame_time)

                if (start_time == 0):
                    start_time = frame_time

                # Verify if file already exists
                ply_path = join(res_path, 'velodyne_frames', frame_name)
                if exists(ply_path):
                    continue

                # Convert to np arrays
                points = np.vstack((data['x'], data['y'], data['z'])).T
                intensity = data['intensity']
                rings = data['ring']
                times = data['time']

                # Save
                write_ply(ply_path,
                          [points, intensity, rings, times],
                          ['x', 'y', 'z', 'intensity', 'ring', 'time'])

            t2 = RealTime.time()
            print("Done in {:.1f}s\n".format(t2 - t1))

        ###################
        # Classified frames
        ###################

        if save_classif:
            
            # read in classified frames
            t1 = RealTime.time()
            print("Reading classified frames")
            frames_bis = bt.read_pointcloud_frames("/classified_points", bag)

            if len(frames_bis):
                if not exists(join(res_path, 'classified_frames')):
                    makedirs(join(res_path, 'classified_frames'))

            # write classified frames to .ply files
            for timestamp, data in frames_bis:

                # Get timestamp
                frame_time = timestamp.to_sec()
                frame_name = "{:.6f}.ply".format(frame_time)

                # Verify if file already exists
                ply_path = join(res_path, 'classified_frames', frame_name)
                if exists(ply_path):
                    continue

                # Convert to np arrays
                points = np.vstack((data['x'], data['y'], data['z'])).T
                intensity = data['intensity']
                classif = data['classif']

                # Save
                write_ply(ply_path,
                          [points, intensity, classif],
                          ['x', 'y', 'z', 'intensity', 'classif'])

            t2 = RealTime.time()
            print("Done in {:.1f}s\n".format(t2 - t1))

        ####################
        # Collider / planner
        ####################

        if save_collider:

            # Collider pickle file path
            t1 = RealTime.time()
            colli_path = join(res_path, 'collider_data.pickle')
            print("Saving collider to", colli_path)

            # Read and save data
            collider_preds = bt.read_collider_preds("/plan_costmap_3D", bag)
            with open(colli_path, 'wb') as handle:
                pickle.dump(collider_preds, handle)


            # Teb plans pickle file path
            teb_path = join(res_path, 'teb_local_plans.pickle')
            print("Saving teb plans to", teb_path)
            
            # Read and save data
            teb_local_plans = bt.read_local_plans("/move_base/TebLocalPlannerROS/local_plan", bag)
            with open(teb_path, 'wb') as handle:
                pickle.dump(teb_local_plans, handle)

            t2 = RealTime.time()
            print("Done in {:.1f}s\n".format(t2 - t1))

        ##############
        # Trajectories
        ##############

        if save_traj:
            t1 = RealTime.time()
            print("Reading trajectories")

            traj_path = join(res_path, 'loc_pose.ply')
            if not exists(traj_path):

                # # read in optimal traj
                # optimal_traj = bt.read_nav_odometry("/optimal_path", bag, False)
                # if (len(optimal_traj)):
                #     pickle_dict['optimal_traj'] = bt.trajectory_to_array(optimal_traj)

                # read in move_base results
                results = bt.read_action_result('/move_base/result', bag)
                action_results = None
                if (len(results)):
                    action_results = results

                # Get the pose of velodyne in odom frame
                odom_to_base = bt.read_tf_transform("odom", "base_link", bag)
                odom_to_base = bt.transforms_to_trajectory(odom_to_base)

                # Get the trajectory in map frame
                map_to_odom = bt.read_tf_transform("map", "odom", bag)
                if len(map_to_odom) < 1:
                    print('Error, no map to odom transform found. Saving odom only')

                    # Save
                    tf_traj_array = bt.trajectory_to_array(odom_to_base, time_origin=start_time)

                    el = ply.PlyElement.describe(tf_traj_array, "trajectory")
                    ply.PlyData([el]).write(traj_path)

                else:
                    # Interpolate map to base
                    print(len(odom_to_base), len(map_to_odom))
                    tf_traj = bt.transform_trajectory(odom_to_base, map_to_odom)

                    # Save
                    tf_traj_array = bt.trajectory_to_array(tf_traj, time_origin=start_time)
                    el = ply.PlyElement.describe(tf_traj_array, "trajectory")
                    ply.PlyData([el]).write(traj_path)

            t2 = RealTime.time()
            print("Done in {:.1f}s\n".format(t2 - t1))

        bag.close()

    return


if __name__ == '__main__':

    main(save_velo=True,
         save_classif=True,
         save_collider=False)
