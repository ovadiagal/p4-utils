#!/bin/bash

# Author: Edgar Costa Molero
# Email: cedgar@ethz.ch

# This script installs all the required software to learn and prototype P4
# programs using the p4lang software suite.

# Furthermore, we install p4-utils and p4-learning and ffr routers.

# This install script has only been tested with the following systems:
# Ubuntu 20.04
# Ubuntu 22.04

# Configuration variables
# Currently loaded linux kernel
KERNEL=$(uname -r)
# non interactive install
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
# username
USER_NAME=$(whoami)
# building directory
BUILD_DIR=~/p4-tools
# number of cores
NUM_CORES=$(grep -c ^processor /proc/cpuinfo)
DEBUG_FLAGS=true
P4_RUNTIME=true
SYSREPO=false   # Sysrepo prevents simple_switch_grpc from starting correctly
FRROUTING=true
DOCUMENTATION=true

# p4-utils branch
P4_UTILS_BRANCH="master"

# Software versions

# PI dependencies from https://github.com/p4lang/PI#dependencies

# protobuf
PROTOBUF_VER="3.20.3"
PROTOBUF_COMMIT="v${PROTOBUF_VER}"

# from https://github.com/p4lang/PI#dependencies
# changed it from 1.43.2 since pip does not have it and my source build fails
GRPC_VER="1.44.0"
GRPC_COMMIT="tags/v${GRPC_VER}"

PI_COMMIT="6d0f3d6c08d595f65c7d96fd852d9e0c308a6f30"    # Aug 21 2023
BMV2_COMMIT="d064664b58b8919782a4c60a3b9dbe62a835ac74"  # Sep 8 2023
P4C_COMMIT="66eefdea4c00e3fbcc4723bd9c8a8164e7288724"   # Sep 13 2023

#FRROUTING_COMMIT="18f209926fb659790926b82dd4e30727311d22aa" # Mar 25 2021
FRROUTING_COMMIT="frr-8.5" # Mar 25 2021

function do_os_message() {
    1>&2 echo "Found ID ${ID} and VERSION_ID ${VERSION_ID} in /etc/os-release"
    1>&2 echo "This script only supports these:"
    1>&2 echo "    ID ubuntu, VERSION_ID in 20.04 22.04"
    1>&2 echo ""
    1>&2 echo "Proceed installing at your own risk."
}

function do_init_checks {
    if [ ! -r /etc/os-release ]
    then
        1>&2 echo "No file /etc/os-release.  Cannot determine what OS this is."
        do_os_message
        exit 1
    fi
    source /etc/os-release

    supported_distribution=0
    if [ "${ID}" = "ubuntu" ]
    then
        case "${VERSION_ID}" in
        20.04)
            supported_distribution=1
            ;;
        22.04)
            supported_distribution=1
            ;;
        esac
    fi

    if [ ${supported_distribution} -eq 1 ]
    then
        echo "Found supported ID ${ID} and VERSION_ID ${VERSION_ID} in /etc/os-release"
    else
        do_os_message
        exit 1
    fi
}

function do_global_setup {
    # Install shared dependencies
    apt-get install -y --no-install-recommends \
    arping \
    autoconf \
    automake \
    bash-completion \
    bridge-utils \
    build-essential \
    ca-certificates \
    cmake \
    cpp \
    curl \
    emacs \
    gawk \
    git \
    git-review \
    g++ \
    htop \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-test-dev \
    libc6-dev \
    libevent-dev \
    libgc-dev \
    libgflags-dev \
    libgmpxx4ldbl \
    libgmp10 \
    libgmp-dev \
    libffi-dev \
    libtool \
    libpcap-dev \
    linux-headers-generic \
    make \
    nano \
    pkg-config \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    tmux \
    traceroute \
    vim \
    wget \
    xcscope-el \
    xterm \
    zip \
    unzip

    # upgrade pip3
    pip3 install --upgrade pip==21.3.1

    # Set Python3 as the default binary
    ln -sf $(which python3) /usr/bin/python
    ln -sf $(which pip3) /usr/bin/pip

    # Install shared dependencies (pip3)
    pip3 install \
    cffi \
    ipaddress \
    ipdb \
    ipython \
    pypcap

    # Install wireshark
    DEBIAN_FRONTEND=noninteractive apt-get -y install wireshark
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure wireshark-common
    apt-get -y --no-install-recommends install \
    tcpdump \
    tshark

    # Install iperf3 (last version)
    apt-get -y --no-install-recommends install iperf3

    # Configure tmux
    wget -O ~/.tmux.conf https://raw.githubusercontent.com/nsg-ethz/p4-utils/${P4_UTILS_BRANCH}/install-tools/conf_files/tmux.conf
}

#### PROTOBUF FUNCTIONS
function do_protobuf {
    echo "Uninstalling Ubuntu python3-protobuf if present"
    apt-get purge -y python3-protobuf || echo "Failed removing protobuf"

    # install python
    pip install protobuf==${PROTOBUF_VER}

    cd ${BUILD_DIR}

    # install from source
    # Clone source
    if [ ! -d protobuf ]; then
        git clone https://github.com/protocolbuffers/protobuf protobuf
    fi

    cd protobuf
    git checkout ${PROTOBUF_COMMIT}
    git submodule update --init --recursive

    # Build protobuf C++
    export CFLAGS="-Os"
    export CXXFLAGS="-Os"
    export LDFLAGS="-Wl,-s"

    ./autogen.sh
    ./configure --prefix=/usr
    make -j${NUM_CORES}
    make install
    ldconfig
    make clean

    unset CFLAGS CXXFLAGS LDFLAGS

    echo "end install protobuf:"
}

function do_grpc {
    # Clone source
    cd ${BUILD_DIR}
    if [ ! -d grpc ]; then
      git clone https://github.com/grpc/grpc.git grpc
    fi
    cd grpc
    git checkout ${GRPC_COMMIT}
    git submodule update --init --recursive

    # Build grpc
    export LDFLAGS="-Wl,-s"

    mkdir -p cmake/build
    cd cmake/build
    cmake ../..
    make
    make install
    ldconfig

    unset LDFLAGS
    echo "grpc installed"
}

PY3LOCALPATH=$(curl -sSL https://raw.githubusercontent.com/nsg-ethz/p4-utils/${P4_UTILS_BRANCH}/install-tools/scripts/py3localpath.py | python3)
function site_packages_fix {
    local SRC_DIR
    local DST_DIR

    SRC_DIR="${PY3LOCALPATH}/site-packages"
    DST_DIR="${PY3LOCALPATH}/dist-packages"

    # When I tested this script on Ubuntu 16.04, there was no
    # site-packages directory.  Return without doing anything else if
    # this is the case.
    if [ ! -d ${SRC_DIR} ]; then
        return 0
    fi

    echo "Adding ${SRC_DIR} to Python3 path..."
    echo "${SRC_DIR}" > ${DST_DIR}/p4-tools.pth
    echo "Done!"
}

function do_bmv2_deps {
    # Install dependencies manually to avoid issues with install_deps.sh
    apt-get install -y \
    git automake libtool build-essential \
    pkg-config libevent-dev libssl-dev \
    libffi-dev python3-dev python3-pip \
    libjudy-dev libgmp-dev \
    libpcap-dev \
    libboost-dev \
    libboost-program-options-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libboost-thread-dev \
    libboost-test-dev \
    libboost-context-dev \
    libboost-coroutine-dev \
    libboost-chrono-dev \
    libboost-date-time-dev \
    libboost-atomic-dev \
    libboost-regex-dev \
    libboost-random-dev \
    libboost-math-dev \
    libboost-serialization-dev \
    libtool-bin \
    valgrind \
    libreadline-dev \
    g++ \
    wget \
    net-tools

    # Install Thrift 0.13.0
    cd ${BUILD_DIR}
    if [ ! -d thrift ]; then
        wget https://dlcdn.apache.org/thrift/0.13.0/thrift-0.13.0.tar.gz
        tar xzf thrift-0.13.0.tar.gz
        mv thrift-0.13.0 thrift
        rm thrift-0.13.0.tar.gz
    fi

    cd thrift
    ./configure --disable-libs --disable-tutorial --disable-tests --without-qt4 --without-qt5 --without-c_glib
    make -j${NUM_CORES}
    make install
    ldconfig
}

# Install behavioral model
function do_bmv2 {
    # Install dependencies
    do_bmv2_deps

    # Clone source
    cd ${BUILD_DIR}
    if [ ! -d bmv2 ]; then
        git clone https://github.com/p4lang/behavioral-model.git bmv2
    fi
    cd bmv2
    git checkout ${BMV2_COMMIT}

    # Modify install_deps.sh to replace libgc1c2 with libgc-dev
    sed -i 's/libgc1c2/libgc-dev/g' install_deps.sh

    # Build behavioral-model
    ./autogen.sh
    if [ "$DEBUG_FLAGS" = true ] && [ "$P4_RUNTIME" = true ]; then
        ./configure --with-pi --with-thrift --with-nanomsg --enable-debugger --disable-elogger
