#!/bin/bash
cat << 'INNER_EOF' > docker/openvins/Dockerfile
FROM ros:humble-ros-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential cmake git libopencv-dev libeigen3-dev \
    python3-colcon-common-extensions python3-rosdep \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
RUN mkdir -p src && cd src && \
    git clone https://github.com/rpng/open_vins.git

# Автоматичне встановлення всіх ROS-залежностей алгоритму
RUN apt-get update && \
    rosdep init || true && \
    rosdep update && \
    rosdep install --from-paths src --ignore-src -r -y

RUN /bin/bash -c "source /opt/ros/humble/setup.bash && colcon build"
INNER_EOF

docker build -t slam_openvins -f docker/openvins/Dockerfile .
