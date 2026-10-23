#!/usr/bin/env bash
set -euo pipefail

JOBS="${JOBS:-2}"
ORB_COMMIT=4452a3c4ab75b1cde34e5505a36ec3f9edcdc4c4
PANGOLIN_TAG=v0.6

sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config \
  libeigen3-dev libopencv-dev libboost-serialization-dev libssl-dev \
  libgl1-mesa-dev libglew-dev libepoxy-dev python3-pip unzip wget

if [ ! -d "$HOME/Pangolin" ]; then
  git clone --branch "$PANGOLIN_TAG" --depth 1 https://github.com/stevenlovegrove/Pangolin.git "$HOME/Pangolin"
fi
mkdir -p "$HOME/Pangolin/build" && cd "$HOME/Pangolin/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$JOBS"
sudo make install
sudo ldconfig

if [ ! -d "$HOME/ORB_SLAM3" ]; then
  git clone https://github.com/UZ-SLAMLab/ORB_SLAM3.git "$HOME/ORB_SLAM3"
fi
cd "$HOME/ORB_SLAM3"
git checkout "$ORB_COMMIT"
sed -i 's/find_package(OpenCV 4.4)/find_package(OpenCV 4.2)/' CMakeLists.txt
sed -i "s/make -j[0-9]*/make -j$JOBS/" build.sh
./build.sh

ls -l Examples/Monocular/mono_tum Examples/RGB-D/rgbd_tum
echo "ORB-SLAM3 build OK"
