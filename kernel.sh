#!/bin/bash

#Settings
KERNEL_VERSION=6.3.2
SYSTEM_VERSION=0.1.0
# make distro directory 
mkdir nautilus
cd nautilus || exit
##################################
# Kernel
##################################
echo "Getting kernel"
#wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz
#tar xf linux-$KERNEL_VERSION.tar.xz
cd linux-$KERNEL_VERSION || exit
# configure kernel (default)
echo "creating configuration"
make defconfig
# compile kernel
echo "compiling kernel"
make -j$(nproc)
# install kernel in project directory 
echo "installing kernel"
mkdir ../kernel-bin
make INSTALL_PATH=../kernel-bin install
cd ..
