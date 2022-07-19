
![Banner](./Data/asrl-banner.png)

# Crystal Ball Navigation.

In this repository, we share the implementation of the paper [Like a Crystal Ball: Self-Supervised Learning to Predict the Future of Dynamic Scenes for Indoor Navigation.](https://arxiv.org/abs/2108.10585).

![Intro figure](./Data/approach.png)


## Intro

We provide the full implementation used in our pipeline, it contains multiple parts: 

- Gazebo simualtion
- Data processing
- Annotation of 3D lidar point clouds.
- Generation of SOGM.
- Training of our network.
- Standard navigation system.
- Standard navigation system with network inference.

Disclaimer: This is research code, it can be messy sometimes, not well optimized, and to make it work on different plateforms, it will probably require some debbugging. but it should work if you follow the intructions

## Data

Our real lidar dataset, UTIn3D, is available [here](https://github.com/utiasASRL/UTIn3D).

The simulated data used in the paper is available in our [old repository](https://github.com/utiasASRL/Deep-Collison-Checker).


## Usage



## Setup 

### Step 1: Docker Image

For convenience we provide a Dockerfile which builds a docker image able to run the code. To build this image simply run the following commands:

```
cd Docker
./docker_build.sh
```

The image will be built following the provided Dockerfile. YOu might need to adapt this file depending on your system. In particular, you might need to change the version of CUDA and thus Pytorch depending on your GPU.

Note that the username inside the docker image is automatically copied from the one used to build the image, to avoid the permission conflicts happening when creating files as root inside a container.


### Step 2: Cpp wrappers 

Our code uses c++ wrappers, like the original KPConv repo. They are very easy to compile. First start a docker container with:

```
cd Scripts
./run_in_container.sh -c " "
```

Then Go to the cpp_wrappers folder and start the compile script.

```
cd cpp_wrappers
./compile_wrappers.sh
```

## Data

### Preprocessed data for fast reproducable results

We provide preprocessed data generated by from our simulator as a zip files:

| Data | Size | Google Drive |
| :--- | :---: | :---: |
| Map + Calib  | ~110MB | [link](https://drive.google.com/file/d/1goRpIItTel5Ourq7WafWGpU4oiqH6bDL/view?usp=sharing) | 
| Bouncers sessions | ~13GB | [link](https://drive.google.com/file/d/11SS0btiHFWX9mmCYcYiHN_eckpJrm5Nu/view?usp=sharing) | 
| Wanderers sessions  | ~14GB | [link](https://drive.google.com/file/d/1sCKXq8qZaArl85lPSrL5k5Gx33hj8C2C/view?usp=sharing) |
| FlowFollowers sessions | ~9GB | [link](https://drive.google.com/file/d/1ximXavqsTSkpF9oneP5vLHqwJ1vdPswl/view?usp=sharing) |

Alternatively, we provide ftp links, for direct download:
- `wget ftp://asrl3.utias.utoronto.ca/2021-Myhal-Simulation/mapping_session.zip`
- `wget ftp://asrl3.utias.utoronto.ca/2021-Myhal-Simulation/bouncers_sessions.zip`
- `wget ftp://asrl3.utias.utoronto.ca/2021-Myhal-Simulation/wanderers_sessions.zip`
- `wget ftp://asrl3.utias.utoronto.ca/2021-Myhal-Simulation/flow_followers_sessions.zip`

First download the map and calibration files. Extract the content in the `./Data` folder. In the folder `./Data/Simulation/slam_offline`, we you will find the preprocessed results of the mapping session: a *.ply* file containing the pointmap of the environment. The folder `./Data/Simulation/calibration` contains the lidar extrinsec calibration.

Then, choose which sessions you want (if not all of them), download and extract them in the `./Data` folder too. You should end up with the folder `./Data/Simulation/simulated_runs`, containing sessions named by dates: `YYYY-MM-DD-HH-MM-SS`.


### Instructions to apply on a different dataset

If you want to use our network on your own data, the most simple solution is to reproduce the exact same format for your own data. 

1) modify the calibration file according to your own lidar calibration.
2) Create a file `./Data/Simulation/slam_offline/YYYY-MM-DD-HH-MM-SS/map_update_0001.ply`. See our [pointmap creation code](SOGM-3D-2D-Net/datasets/MyhalCollision.py#L1724) for how to create such a map. 
3) Organise every data folder in `./Data/Simulation/simulated_runs` as follows:

```
    #   YYYY-MM-DD-HH-MM-SS
    #   |
    #   |---logs-YYYY-MM-DD-HH-MM-SS
    #   |   |
    #   |   |---map_traj.ply         # (OPTIONAL) map_poses = loc_poses (x, y, z, qx qy, qz, qw)
    #   |   |---pointmap_00000.ply   # (OPTIONAL) pointmap of this particular session
    #   |
    #   |---sim_frames
    #   |   |
    #   |   |---XXXX.XXXX.ply  # .ply file for each frame point cloud (x, y, z) in lidar corrdinates.
    #   |   |---XXXX.XXXX.ply
    #   |   |--- ...
    #   |
    #   |---gt_pose.ply  # (OPTIONAL) groundtruth poses (x, y, z, qx, qy, qz, qw)
    #   |
    #   |---loc_pose.ply  # localization poses (x, y, z, qx, qy, qz, qw)
```

4) You will have to modify the paths ans parameters according to your new data [here](SOGM-3D-2D-Net/train_MyhalCollision.py#L283-L303). Also choose which folder you use as validation [here](SOGM-3D-2D-Net/train_MyhalCollision.py#L312)

5) If there are errors along the way, try to follow the code execution and correct the possible mistakes


## Run the Annotation and Network

We provide a script to run the code inside a docker container using the image in the `./Docker` folder. Simply start it with:

```
cd Scripts
./run_in_container.sh
```

This script runs a command inside the `./SOGM-3D-2D-Net` folder. Without any argument the command is: `python3 train_MyhalCollision.py`. This script first annotated the data and creates preprocessed 2D+T point clouds in `./Data/Simulation/collisions`. Then it starts the training on this data, generating SOGMs from the preprocessed 2D+T clouds

You can choose to execute another command inside the docker container with the argument `-c`. For example, you can plot the current state of your network training with:

```
cd Scripts
./run_in_container.sh -c "python3 collider_plots.py"
```

You can also add the argument -d to run the container in detach mode (very practical as the training lasts several hours).


## Building a dev environment using Docker and VSCode

We provide a simple way to develop over our code using Docker and VSCode. First start a docker container specifically for development:

```
cd Scripts
./dev_noetic.sh -d
```

Then then attach visual studio code to this container named `$USER-noetic_pytorch-dev`. For this you need to install the docker extension, then go to the list of docker containers running, right click on `$USER-noetic_pytorch-dev`, and `attach visual studio code`.

You can even do it over shh by forwarding the right port. Execute the following commands (On windows, it can be done using MobaXterm local terminal):

```
set DOCKER_HOST="tcp://localhost:23751"
ssh -i "path_to_your_ssh_key" -NL localhost:23751:/var/run/docker.sock  user@your_domain_or_ip
```

The list of docker running on your remote server should appear in the list of your local VSCode. YOu will probably need the extensions `Remote-SSH` and `Remote-Containers`.


## Going further

If you are interested in using this code with our simulator, you can go to the two following repositories:

- [https://github.com/utiasASRL/MyhalSimulator](https://github.com/utiasASRL/MyhalSimulator)

- [https://github.com/utiasASRL/MyhalSimulator-DeepCollider](https://github.com/utiasASRL/MyhalSimulator-DeepCollider)

The first one contains the code to run our Gazebo simulations, and the second on contains the code to perform online predictions within the simulator. Note though, that these repositories are still in developpement and are not as easily run as this one.


## Reference

If you are to use this code, please cite our paper

```
@article{thomas2021learning,
    Author = {Thomas, Hugues and Gallet de Saint Aurin, Matthieu and Zhang, Jian and Barfoot, Timothy D.},
    Title = {Learning Spatiotemporal Occupancy Grid Maps for Lifelong Navigation in Dynamic Scenes},
    Journal = {arXiv preprint arXiv:2108.10585},
    Year = {2021}
}
```

## License
Our code is released under MIT License (see LICENSE file for details).
