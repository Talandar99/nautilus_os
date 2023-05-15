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
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz
tar xf linux-$KERNEL_VERSION.tar.xz
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

##################################
# create filesystem
##################################
echo "creating all directories"
mkdir rootfs
mkdir rootfs/dev 
mkdir rootfs/proc 
mkdir rootfs/sys 
mkdir rootfs/bin
mkdir rootfs/tmp
mkdir rootfs/root
mkdir rootfs/nix
mkdir rootfs/etc 
mkdir rootfs/etc/nix/
mkdir rootfs/etc/ssl/
mkdir rootfs/etc/ssl/certs

##################################
#create configuration files
##################################
touch rootfs/etc/group
touch rootfs/etc/passwd
echo "build-users-group = nixbld" > rootfs/etc/nix/nix.conf
echo "build-users = 8" >> rootfs/etc/nix/nix.conf
#add configuration to profile
echo "export SSL_CERT_DIR=/etc/ssl/certs" > rootfs/etc/profile
echo "source /nix/var/nix/profiles/default/etc/profile.d/nix.sh" >> rootfs/etc/profile
#add system name and version
echo "NAME=\"Nautilus\"" > rootfs/etc/os-release
echo "VERSION=\"$SYSTEM_VERSION\"" >> rootfs/etc/os-release
echo "ID=nautilus" >> rootfs/etc/os-release
echo "PRETTY_NAME=\"Nautilus $SYSTEM_VERSION⚓\"" >> rootfs/etc/os-release

##################################
#create nix installation sctipt
##################################
curl -L https://nixos.org/nix/install >> rootfs/nix.sh
chmod +x rootfs/nix.sh

##################################
# Bussybox
##################################
echo "getting bussybox static executable"
wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x busybox
mv busybox rootfs/bin/busybox

##################################
# create symlinks for busybox
##################################
echo "creating symlinks"
cd rootfs/bin	
for prog in $(./busybox --list); do
		ln -s /bin/busybox $prog
done
cd ../..

##################################
#install curl and certificates
##################################
wget https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64
mv curl-amd64 curl
chmod +x curl
mv curl rootfs/bin/curl

##################################
# Dockerfile
##################################
echo "creating Dockerfile"
echo "FROM scratch" > Dockerfile
# add kernel
echo "COPY kernel-bin/vmlinuz /" >> Dockerfile
# add filesystem
echo "COPY rootfs/ /" >> Dockerfile
# default shell
echo "SHELL [\"/bin/sh\", \"-c\"]" >> Dockerfile
# get certifocates
echo "RUN wget https://curl.haxx.se/ca/cacert.pem -O /etc/ssl/certs/ca-certificates.crt" >> Dockerfile
# set user as root
echo "ENV USER=root" >> Dockerfile
#install nix
echo "RUN addgroup --system nixbld" >> Dockerfile
echo "RUN adduser --system --home /var/empty --shell /sbin/nologin --no-create-home --ingroup nixbld nixbld" >> Dockerfile
echo "RUN ./nix.sh" >> Dockerfile
echo "RUN rm nix.sh" >> Dockerfile
echo "ENV PATH=\"/nix/var/nix/profiles/default/bin:\${PATH}\"" >> Dockerfile
echo "RUN nix-env -i neofetch-unstable" >> Dockerfile

##################################
# build container and run
##################################
echo "creating build_and_run.sh"
echo "#!/bin/bash" > build_and_run.sh
echo "docker buildx build -t nautilus ." >> build_and_run.sh
echo "docker run -it nautilus bin/sh" >> build_and_run.sh
chmod +x build_and_run.sh
echo "building and running container"
./build_and_run.sh
