#!/bin/bash

# Configuration variables
KERNEL=$(uname -r)
DEBIAN_FRONTEND=noninteractive sudo apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
USER_NAME=$(whoami)
BUILD_DIR=~/p4-tools
NUM_CORES=$(grep -c ^processor /proc/cpuinfo)
DEBUG_FLAGS=true
P4_RUNTIME=true
SYSREPO=false
FRROUTING=true
DOCUMENTATION=true
P4_UTILS_BRANCH="master"
PROTOBUF_VER="3.20.3"
PROTOBUF_COMMIT="v${PROTOBUF_VER}"
GRPC_VER="1.44.0"
GRPC_COMMIT="tags/v${GRPC_VER}"
PI_COMMIT="6d0f3d6c08d595f65c7d96fd852d9e0c308a6f30"
BMV2_COMMIT="d064664b58b8919782a4c60a3b9dbe62a835ac74"
P4C_COMMIT="66eefdea4c00e3fbcc4723bd9c8a8164e7288724"
FRROUTING_COMMIT="frr-8.5"

function do_global_setup {
    # Install shared dependencies, excluding kernel headers and replacing libgc1c2 with libgc1
    sudo apt-get install -y --no-install-recommends \
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
    libgc1 \
    libgflags-dev \
    libgmpxx4ldbl \
    libgmp10 \
    libgmp-dev \
    libffi-dev \
    libtool \
    libpcap-dev \
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
    unzip \
    locales

    # Set up locale
    sudo locale-gen en_US.UTF-8

    # Upgrade pip3 and set Python3 as the default binary
    sudo pip3 install --upgrade pip==21.3.1
    sudo ln -sf $(which python3) /usr/bin/python
    sudo ln -sf $(which pip3) /usr/bin/pip

    # Install shared dependencies (pip3)
    sudo pip3 install \
    cffi \
    ipaddress \
    ipdb \
    ipython \
    pypcap

    # Install wireshark, tcpdump, and tshark without requiring interaction
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wireshark
    echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure wireshark-common
    sudo apt-get -y --no-install-recommends install tcpdump tshark

    # Install iperf3
    sudo apt-get -y --no-install-recommends install iperf3

    # Configure tmux
    wget -O ~/.tmux.conf https://raw.githubusercontent.com/nsg-ethz/p4-utils/${P4_UTILS_BRANCH}/install-tools/conf_files/tmux.conf
}

# Continue with the rest of the functions as they were, but without installing `linux-headers-$KERNEL`

function do_init_checks {
    if [ ! -r /etc/os-release ]; then
        1>&2 echo "No file /etc/os-release.  Cannot determine what OS this is."
        exit 1
    fi
    source /etc/os-release
    supported_distribution=0
    if [ "${ID}" = "ubuntu" ] && ([ "${VERSION_ID}" = "20.04" ] || [ "${VERSION_ID}" = "22.04" ]); then
        supported_distribution=1
    fi
    if [ ${supported_distribution} -eq 0 ]; then
        1>&2 echo "Unsupported OS version."
        exit 1
    fi

    # check for at least 35G disk space
    if [ $(df --output=size -BG / | tail -1 | tr -d 'G ') -lt 35 ]; then
        echo "You have less than 35G of total disk space."; 
        exit 1
    fi
}

# Continue with other functions as they were, then finalize by calling the main install functions
do_init_checks
do_global_setup

# Print commands and exit on errors
set -xe

echo "------------------------------------------------------------"
echo "Time and disk space used before installation begins:"
set -x
date
df -h .
df -BM .

# Make system passwordless
if [ ! -f /etc/sudoers.d/99_vm ]; then
    sudo bash -c "echo '${USER_NAME} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99_vm"
    sudo chmod 440 /etc/sudoers.d/99_vm
fi

# Create BUILD_DIR
mkdir -p ${BUILD_DIR}

# Install P4 tools
do_protobuf
if [ "$P4_RUNTIME" = true ]; then
    do_grpc
    do_bmv2_deps
    if [ "$SYSREPO" = true ]; then
        do_sysrepo_libyang
    fi
    do_PI
fi

# python site packages fix
site_packages_fix

do_bmv2
do_p4c
do_ptf
do_mininet_no_python2

if [ "$FRROUTING" = true ]; then
    do_frrouting
fi

do_p4-utils
do_p4-learning

if [ "$DOCUMENTATION" = true ]; then
    do_sphinx
fi

#echo "Installation complete!"
