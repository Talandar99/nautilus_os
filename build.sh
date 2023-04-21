#!/bin/bash
# make distro directory 
mkdir nautilus
cd nautilus || exit

# Get Kernel
echo "Getting kernel"
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.2.tar.xz
tar xf linux-6.2.tar.xz
cd linux-6.2 || exit

echo "creating configuration"
# configure kernel (default)
make defconfig

echo "compiling kernel"
# compile kernel
make -j$(nproc)

# install kernel in project directory 
echo "installing kernel"
mkdir ../kernel-bin
make INSTALL_PATH=../kernel-bin install
cd ..

# get BusyBox
echo "getting bussybox static executable"
wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
echo "creating all directories"
mkdir rootfs
# create filesystem
mkdir -p rootfs/dev rootfs/etc rootfs/proc rootfs/sys rootfs/bin
# add +x to bussybox
chmod +x busybox
mv busybox rootfs/bin/busybox
# create symlinks for busybox
echo "creating symlinks"
cd rootfs/bin	
for prog in $(./busybox --list); do
		ln -s /bin/busybox $prog
done
cd ../..

echo "creating Dockerfile"
# create Dockerfile
echo "FROM scratch" > Dockerfile
echo "COPY kernel-bin/vmlinuz /" >> Dockerfile
echo "COPY rootfs/ /" >> Dockerfile

echo "creating build_and_run.sh"
# build docker container and run it
echo "#!/bin/bash" > build_and_run.sh
echo "docker buildx build -t nautilus ." >> build_and_run.sh
echo "docker run -it nautilus bin/sh" >> build_and_run.sh
chmod +x build_and_run.sh
echo "building and running container"
./build_and_run.sh
