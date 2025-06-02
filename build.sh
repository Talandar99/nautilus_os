#!/usr/bin/env bash


RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'


SYSTEM_VERSION="0.2.0"
DISTRO_DIR="nautilus"
ROOTFS_DIR="${DISTRO_DIR}/rootfs"

#BUILD_ARCHITECTURE="AMD64"
BUILD_ARCHITECTURE="AARCH64"

if [ "$BUILD_ARCHITECTURE" = "AMD64" ]; then
  ARCH="x86_64"
  CROSS_COMPILE=""                            # for x86_64 (native build)
else
  ARCH="aarch64"
  CROSS_COMPILE="aarch64-unknown-linux-gnu-"  # for aarch64 (cross-compilation)
fi

function setup_dirs() {
    echo -e "${YELLOW}setup_dirs${RESET}"
    mkdir -p "${ROOTFS_DIR}/dev" 
    mkdir -p "${ROOTFS_DIR}/proc" 
    mkdir -p "${ROOTFS_DIR}/sys" 
    mkdir -p "${ROOTFS_DIR}/bin" 
    mkdir -p "${ROOTFS_DIR}/tmp" 
    mkdir -p "${ROOTFS_DIR}/root" 
    mkdir -p "${ROOTFS_DIR}/etc/ssl/certs"
}

function create_configs() {
    echo -e "${YELLOW}create_configs${RESET}"

    touch "${ROOTFS_DIR}/etc/group"
    touch "${ROOTFS_DIR}/etc/passwd"

    echo "export SSL_CERT_DIR=/etc/ssl/certs"             | tee       "${ROOTFS_DIR}/etc/profile"     > /dev/null

    echo "NAME=\"Nautilus\""                              | tee       "${ROOTFS_DIR}/etc/os-release"  > /dev/null
    echo "VERSION=\"${SYSTEM_VERSION}\""                  | tee -a    "${ROOTFS_DIR}/etc/os-release"  > /dev/null
    echo "ID=nautilus"                                    | tee -a    "${ROOTFS_DIR}/etc/os-release"  > /dev/null
    echo "PRETTY_NAME=\"Nautilus ${SYSTEM_VERSION}⚓\""   | tee -a    "${ROOTFS_DIR}/etc/os-release"  > /dev/null
}

function compile_and_install_busybox() {
    BUSYBOX_VERSION="1.36.1"
    BUSSYBOX_COMPILE_DIR="busybox_build"

    echo -e "${YELLOW}compile_and_install_busybox${RESET}"
    echo -e "${BLUE}---getting files---${RESET}"
    mkdir -p "$BUSSYBOX_COMPILE_DIR"
    cd "$BUSSYBOX_COMPILE_DIR" 

    if [ ! -f "busybox-$BUSYBOX_VERSION.tar.bz2" ]; then
        wget "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
    fi
    if [ ! -d "busybox-$BUSYBOX_VERSION" ]; then
      tar -xjf "busybox-$BUSYBOX_VERSION.tar.bz2"
    fi

    cd "busybox-$BUSYBOX_VERSION"
    
    echo -e "${BLUE}---compiling---${RESET}"
    make distclean || true
    make defconfig 
    #static build
    echo "CONFIG_STATIC=y" >> .config
    #disable problematic tool
    sed -i 's/.*CONFIG_TC.*/# CONFIG_TC is not set/' .config
    #enable unset thing
    echo "CONFIG_TCPSVD=y" >> .config
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" install CONFIG_PREFIX="$BUSSYBOX_COMPILE_DIR/_install/$ARCH"
    #sudo chown root:root busybox
    #sudo chmod u+s busybox
    cd ../..
    pwd
    cp "$BUSSYBOX_COMPILE_DIR/busybox-$BUSYBOX_VERSION/busybox" "${ROOTFS_DIR}/bin/busybox"

    echo -e "${BLUE}---installing busybox in nautilus---${RESET}"
    cd "${ROOTFS_DIR}/bin"

    while read -r prog; do
        ln -sf /bin/busybox "$prog"
    done < ../../../busybox_applets

    cd ../../..
    pwd
}

function compile_and_install_nginx() {
    NGINX_VERSION="1.27.3"
    NGINX_BUILD_DIR="nginx_build"
    NGINX_INSTALL_DIR="${ROOTFS_DIR}/usr/local/nginx"

    echo -e "${YELLOW}compile_and_install_nginx${RESET}"
    echo -e "${BLUE}---getting files---${RESET}"
    mkdir -p "$NGINX_BUILD_DIR"
    cd "$NGINX_BUILD_DIR"

    if [ ! -f "nginx-$NGINX_VERSION.tar.gz" ]; then
        wget "http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
    fi
    if [ ! -d "nginx-$NGINX_VERSION" ]; then
        tar -xzf "nginx-$NGINX_VERSION.tar.gz"
    fi

    cd "nginx-$NGINX_VERSION"

    echo -e "${BLUE}---configuring---${RESET}"
    
    ./configure \
        --prefix="$NGINX_INSTALL_DIR" \
        --with-cc="/usr/bin/aarch64-unknown-linux-gnu-gcc "\
        --with-ld-opt="-static" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-stream \
        --with-stream_ssl_module

    echo -e "${BLUE}---compiling---${RESET}"
    make -j"$(nproc)" CROSS_COMPILE="$CROSS_COMPILE" || { echo "Make failed"; exit 1; }

    echo -e "${BLUE}---installing---${RESET}"
    make install

    cd ../..
    echo -e "${GREEN}nginx installed to $NGINX_INSTALL_DIR${RESET}"
}

function install_curl() {
  echo -e "${YELLOW}--- install_curl ---${RESET}\n"
  wget https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64 -O curl
  chmod +x curl
  mv curl "${ROOTFS_DIR}/bin/curl"
}

function install_musl_gcc() {
  echo -e "${YELLOW}--- install_musl_gcc ---${RESET}\n"
  wget https://musl.cc/x86_64-linux-musl-cross.tgz
  tar -xzf x86_64-linux-musl-cross.tgz
  mv x86_64-linux-musl-cross/bin/x86_64-linux-musl-gcc "${ROOTFS_DIR}/bin/gcc"
  rm -rf x86_64-linux-musl-cross x86_64-linux-musl-cross.tgz
}

function install_make() {
  echo -e "${BLUE}--- install_make ---${RESET}\n"
  wget https://ftp.gnu.org/gnu/make/make-4.4.tar.gz
  tar -xzf make-4.4.tar.gz
  cd make-4.4
  ./configure LDFLAGS=-static
  make
  cd ..
  mv make-4.4/make "${ROOTFS_DIR}/bin/make"
  rm -rf make-4.4 make-4.4.tar.gz*
}

function main(){
    setup_dirs
    create_configs
    #compile_and_install_busybox
    compile_and_install_nginx
}
main
