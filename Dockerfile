FROM ros:humble-ros-base-jammy

# Put everything in spot folder.
RUN mkdir -p /spot
COPY . /spot
WORKDIR /spot

# setup environment
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

ARG ROS_DISTRO=humble
ENV ROS_DISTRO $ROS_DISTRO
ARG INSTALL_PACKAGE=base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN DEBIAN_FRONTEND=noninteractive apt-get update -q && \
  apt-get update -q && \
  apt-get install -yq --no-install-recommends \
  wget \
  lcov \
  curl \
  python3-pip \
  python-is-python3 \
  python3-argcomplete \
  python3-colcon-common-extensions \
  python3-colcon-mixin \
  python3-rosdep \
  libpython3-dev \
  python3-vcstool \
  ros-humble-tl-expected && \
  rm -rf /var/lib/apt/lists/*

# Install bosdyn_msgs package
RUN curl -sL https://github.com/bdaiinstitute/bosdyn_msgs/releases/download/4.0.2/ros-humble-bosdyn_msgs_4.0.2-jammy_arm64.run --output /tmp/ros-humble-bosdyn_msgs_4.0.2-jammy_arm64.run --silent \
  && chmod +x /tmp/ros-humble-bosdyn_msgs_4.0.2-jammy_arm64.run \
  && ((yes || true) | /tmp/ros-humble-bosdyn_msgs_4.0.2-jammy_arm64.run) \
  && rm /tmp/ros-humble-bosdyn_msgs_4.0.2-jammy_arm64.run

# Install spot_cpp_sdk package
RUN curl -sL https://github.com/bdaiinstitute/spot-cpp-sdk/releases/download/v4.0.2/spot-cpp-sdk_4.0.2_arm64.deb --output /tmp/spot-cpp-sdk_4.0.2_arm64.deb --silent \
  && dpkg -i /tmp/spot-cpp-sdk_4.0.2_arm64.deb \
  && rm /tmp/spot-cpp-sdk_4.0.2_arm64.deb

# Install bosdyn_msgs missing dependencies
RUN python -m pip install --no-cache-dir --upgrade pip==22.3.1 \
  && pip install --root-user-action=ignore --no-cache-dir --default-timeout=900 \
  numpy==1.24.1 \
  pytest-cov==4.1.0 \
  pytest-xdist==3.5.0 \
  bosdyn-api==4.0.2 \
  bosdyn-core==4.0.2 \
  bosdyn-client==4.0.2 \
  bosdyn-mission==4.0.2 \
  bosdyn-choreography-client==4.0.2 \
  && pip cache purge

# Install spot_wrapper requirements
RUN pip install --root-user-action=ignore --no-cache-dir --default-timeout=900 -r /spot/spot_wrapper/requirements.txt && \
  pip cache purge

# Install packages dependencies
RUN apt-get update -q && rosdep update && \
  rosdep install -y -i --from-paths /spot --skip-keys "bosdyn bosdyn_msgs spot_wrapper" && \
  rm -rf /var/lib/apt/lists/*

# ROS doesn't recognize the docker shells as terminals so force colored output
ENV RCUTILS_COLORIZED_OUTPUT=1

# Create Spot user in container
RUN useradd -ms /bin/bash spot && \
  passwd -d spot && \
  adduser spot sudo && \
  adduser spot video

RUN chown spot /spot
RUN chown -Rv spot /spot/*
RUN chmod -Rv a+x /spot/*
RUN chown -Rv spot:spot /opt/ros/${ROS_DISTRO}/*
RUN chmod -Rv a+x /opt/ros/${ROS_DISTRO}/*
RUN chown -Rv spot:spot /opt/ros/${ROS_DISTRO}/*

ENV ament_cmake_DIR=/opt/ros/${ROS_DISTRO}/share/ament_cmake/cmake


RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /home/spot/.bashrc
USER spot

# Log Colcon issues to /tmp
RUN mkdir -p /tmp/colcon-logs/
RUN mkdir -p /spot/build/
ENV COLCON_LOG_PATH=/tmp/colcon-logs/

WORKDIR /spot
RUN sudo chmod -R u+w .
RUN ./install_spot_ros2.sh --arm64

SHELL ["bash", "-c"]

RUN colcon build --symlink-install --packages-ignore proto2ros_tests --build-base /spot/build
RUN echo "source /spot/install/setup.bash" >> /home/spot/.bashrc

ENTRYPOINT ["bash", "-c", "source /home/spot/.bashrc && bash"] 
