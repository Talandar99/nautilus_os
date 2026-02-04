#!/usr/bin/env bash


RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'


SYSTEM_VERSION="0.2.0"
DISTRO_DIR="nautilus"
ROOTFS_DIR="${DISTRO_DIR}/rootfs"

BUILD_ARCHITECTURE="AMD64"
#BUILD_ARCHITECTURE="AARCH64"

if [ "$BUILD_ARCHITECTURE" = "AMD64" ]; then
  ARCH="x86_64"
  CROSS_COMPILE="x86_64-linux-musl-"
else
  ARCH="aarch64"
  CROSS_COMPILE="aarch64-unknown-linux-musl-"
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

    echo 'root:x:0:0:root:/root:/bin/sh' >> "${ROOTFS_DIR}/etc/passwd"
    echo 'nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin' >> "${ROOTFS_DIR}/etc/passwd"
    echo 'root:x:0:' >> "${ROOTFS_DIR}/etc/group"
    echo 'users:x:100:' >> "${ROOTFS_DIR}/etc/group"
}

function compile_and_install_busybox() {
    BUSYBOX_VERSION="1.36.1"
    BUSYBOX_COMPILE_DIR="busybox_build"
    INSTALL_DIR="$BUSYBOX_COMPILE_DIR/_install"
    
    echo -e "${YELLOW}compile_and_install_busybox${RESET}"
    echo -e "${BLUE}---getting files---${RESET}"
    mkdir -p "$BUSYBOX_COMPILE_DIR"
    cd "$BUSYBOX_COMPILE_DIR"

    if [ ! -f "busybox-$BUSYBOX_VERSION.tar.bz2" ]; then
        wget "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
    fi

    if [ ! -d "busybox-$BUSYBOX_VERSION" ]; then
        tar -xjf "busybox-$BUSYBOX_VERSION.tar.bz2"
    fi

    cd "busybox-$BUSYBOX_VERSION"

    echo -e "${BLUE}---compiling---${RESET}"
    make distclean || true
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig

    # Static build
    echo "CONFIG_STATIC=y" >> .config
    sed -i 's/^CONFIG_EXTRA_CFLAGS=".*"/CONFIG_EXTRA_CFLAGS="-static"/' .config

    sed -i 's/.*CONFIG_TC.*/# CONFIG_TC is not set/' .config
    echo "CONFIG_TCPSVD=y" >> .config
    cat .config | tail

    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CONFIG_EXTRA_CFLAGS="-static" -j$(nproc)
    #make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc)

    make install CONFIG_PREFIX="../../$INSTALL_DIR"

    cd ../..

    # Copy binary
    mkdir -p "${ROOTFS_DIR}/bin"
    cp "$INSTALL_DIR/bin/busybox" "${ROOTFS_DIR}/bin/busybox"

    # check 
    echo -e "${BLUE}---checking if busybox is statically linked---${RESET}"
    file "${ROOTFS_DIR}/bin/busybox" | grep -q "statically linked" || {
        echo -e "${RED}ERROR: BusyBox is not statically linked!${RESET}"
        exit 1
    }

    echo -e "${BLUE}---installing busybox applets in nautilus---${RESET}"
    cd "${ROOTFS_DIR}/bin"

    # Use existing list
    while read -r prog; do
        ln -sf /bin/busybox "$prog"
    done < ../../../busybox_applets

    cd ../../..

    #rm -rf "$BUSYBOX_COMPILE_DIR"
}

function get_and_install_nginx() {
    #nginx does not support cross compiling
    echo -e "${YELLOW}get_and_install_nginx${RESET}"

    NGINX_VERSION="1.28.0"
    NGINX_INSTALL_DIR="${ROOTFS_DIR}/usr/local/nginx"

    if [ "$BUILD_ARCHITECTURE" = "AMD64" ]; then
        ARCH="x86_64"
    else
        ARCH="aarch64"
    fi

    NGINX_BINARY="nginx-${NGINX_VERSION}-${ARCH}-linux"
    NGINX_URL="https://github.com/common-binaries/nginx/raw/binaries/${NGINX_BINARY}"
    mkdir -p "$NGINX_INSTALL_DIR/sbin"

    echo -e "${BLUE}---downloading binary---${RESET}"
    wget "$NGINX_URL" -O "$NGINX_INSTALL_DIR/sbin/nginx"
    chmod +x "$NGINX_INSTALL_DIR/sbin/nginx"

    echo -e "${GREEN}nginx installed in $NGINX_INSTALL_DIR${RESET}"

    mkdir -p "$NGINX_INSTALL_DIR/conf"

    echo -e "${BLUE}---generating default nginx.conf---${RESET}"
    {
        echo "user root;"
        echo "worker_processes  1;"
        echo ""
        echo "events {"
        echo "    worker_connections  1024;"
        echo "}"
        echo ""
        echo "http {"
        echo "    include       mime.types;"
        echo "    default_type  application/octet-stream;"
        echo ""
        echo "    sendfile        on;"
        echo "    keepalive_timeout  65;"
        echo ""
        echo "    server {"
        echo "        listen       80;"
        echo "        server_name  localhost;"
        echo ""
        echo "        location / {"
        echo "            root   /usr/local/nginx/html;"
        echo "            index  index.html index.htm;"
        echo "        }"
        echo ""
        echo "        error_page   500 502 503 504  /50x.html;"
        echo "        location = /50x.html {"
        echo "            root   html;"
        echo "        }"
        echo "    }"
        echo "}"
    } > "$NGINX_INSTALL_DIR/conf/nginx.conf"
    #get and add mimetypes
    wget https://raw.githubusercontent.com/nginx/nginx/master/conf/mime.types -O "$NGINX_INSTALL_DIR/conf/mime.types"
    
    #add welcome page
    mkdir -p "${ROOTFS_DIR}/usr/local/nginx/html"
    echo "<html><body><h1>Welcome to Nautilus nginx!</h1></body></html>" > "${ROOTFS_DIR}/usr/local/nginx/html/index.html"
    
    echo -e "${GREEN}Default nginx.conf created in $NGINX_INSTALL_DIR/conf${RESET}"
}

function get_and_install_beszel() {
    BESZEL_TAG="v0.11.1"
    if [ "$BUILD_ARCHITECTURE" = "AMD64" ]; then
        GOARCH="amd64"
    else
        GOARCH="arm64"
    fi

    mkdir beszel
    cd beszel

    echo -e "${YELLOW}getting_beszel_agent${RESET}"
    wget "https://github.com/henrygd/beszel/releases/download/${BESZEL_TAG}/beszel-agent_linux_${GOARCH}.tar.gz"
    tar xvf "beszel-agent_linux_${GOARCH}.tar.gz"
    
    echo -e "${YELLOW}getting_beszel${RESET}"
    wget "https://github.com/henrygd/beszel/releases/download/${BESZEL_TAG}/beszel_linux_${GOARCH}.tar.gz" 
    tar xvf "beszel_linux_${GOARCH}.tar.gz"

    cd ..

    echo -e "${YELLOW}installing beszel${RESET}"
    mkdir -p "${ROOTFS_DIR}/usr/local/bin"
    cp beszel/beszel "${ROOTFS_DIR}/usr/local/bin/"
    cp beszel/beszel-agent "${ROOTFS_DIR}/usr/local/bin/"

    rm -rf beszel
}

get_and_install_curl(){
    if [ "$BUILD_ARCHITECTURE" = "AMD64" ]; then
        CURLARCH="amd64"
    else
        CURLARCH="arm64"
    fi
    echo -e "${YELLOW}installing curl${RESET}"
	wget https://github.com/moparisthebest/static-curl/releases/latest/download/curl-${CURLARCH} -O curl
	chmod +x curl
	mv curl ${ROOTFS_DIR}/bin/curl
}

get_and_install_lua() {
    LUA_VERSION="5.4.6"
    LUA_TARBALL="lua-${LUA_VERSION}.tar.gz"
    LUA_URL="https://www.lua.org/ftp/${LUA_TARBALL}"
    LUA_BUILD_DIR="lua_build"

    mkdir -p "$LUA_BUILD_DIR"
    
    cd "$LUA_BUILD_DIR" || exit 1
    [ -f "$LUA_TARBALL" ] || wget "$LUA_URL" -O "$LUA_TARBALL" || exit 1
    
    rm -rf "lua-${LUA_VERSION}"
    tar xvf "$LUA_TARBALL" || exit 1
    cd "lua-${LUA_VERSION}" || exit 1

    make clean || true
    make linux -j"$(nproc)" \
        CC="${CROSS_COMPILE}gcc" \
        AR="${CROSS_COMPILE}ar rcu" \
        RANLIB="${CROSS_COMPILE}ranlib" \
        MYCFLAGS="-O2 -static" \
        MYLDFLAGS="-static" || exit 1

    cp -f src/lua  "../../${ROOTFS_DIR}/bin/lua"  || exit 1
    cp -f src/luac "../../${ROOTFS_DIR}/bin/luac" || exit 1

    cd ../.. || exit 1
}

build_install_oniguruma() {
    ONU_VERSION="6.9.9"
    ONU_TARBALL="onig-${ONU_VERSION}.tar.gz"
    ONU_URL="https://github.com/kkos/oniguruma/releases/download/v${ONU_VERSION}/${ONU_TARBALL}"
    ONU_DIR="oniguruma_build"
    SYSROOT_DIR="deps_sysroot"
    HOST="${CROSS_COMPILE%-}"

    mkdir -p "$ONU_DIR" "$SYSROOT_DIR"
    cd "$ONU_DIR" || exit 1

    [ -f "$ONU_TARBALL" ] || wget "$ONU_URL" -O "$ONU_TARBALL" || exit 1

    rm -rf "onig-${ONU_VERSION}"
    tar xvf "$ONU_TARBALL" || exit 1
    cd "onig-${ONU_VERSION}" || exit 1

    make distclean >/dev/null 2>&1 || true

    CC="${CROSS_COMPILE}gcc" \
    AR="${CROSS_COMPILE}ar" \
    RANLIB="${CROSS_COMPILE}ranlib" \
    CFLAGS="-O2 -static -std=gnu17 -Wno-error=incompatible-pointer-types" \
    ./configure \
        --host="$HOST" \
        --prefix="$(pwd)/../../${SYSROOT_DIR}/usr" \
        --disable-shared \
        --enable-static || exit 1

    make -j"$(nproc)" || exit 1
    make install || exit 1

    cd ../.. || exit 1
}

get_and_install_jq() {
    JQ_VERSION="1.7.1"
    JQ_TARBALL="jq-${JQ_VERSION}.tar.gz"
    JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${JQ_TARBALL}"
    JQ_DIR="jq_build"
    SYSROOT_DIR="deps_sysroot"
    HOST="${CROSS_COMPILE%-}"

    build_install_oniguruma

    mkdir -p "$JQ_DIR"
    cd "$JQ_DIR" || exit 1

    [ -f "$JQ_TARBALL" ] || wget "$JQ_URL" -O "$JQ_TARBALL" || exit 1

    rm -rf "jq-${JQ_VERSION}"
    tar xvf "$JQ_TARBALL" || exit 1
    cd "jq-${JQ_VERSION}" || exit 1

    make distclean >/dev/null 2>&1 || true

    CPPFLAGS="-I$(pwd)/../../${SYSROOT_DIR}/usr/include"
    # WAŻNE: -static zostaw, ale do pełnej statyczności dodamy -all-static przy linku
    LDFLAGS="-L$(pwd)/../../${SYSROOT_DIR}/usr/lib -static"
    LIBS="-lonig"

    # bez -static tutaj
    CFLAGS="-O2 -std=gnu17 -Wno-error -Wno-error=incompatible-pointer-types"

    CC="${CROSS_COMPILE}gcc" \
    AR="${CROSS_COMPILE}ar" \
    RANLIB="${CROSS_COMPILE}ranlib" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure \
        --host="$HOST" \
        --disable-shared \
        --enable-static \
        --without-docs || exit 1

    # KLUCZ: libtool wymaga -all-static na etapie linkowania programu
    make -j"$(nproc)" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS -all-static" \
        LIBS="$LIBS" || exit 1

    mkdir -p "../../${ROOTFS_DIR}/bin"
    cp -f jq "../../${ROOTFS_DIR}/bin/jq" || exit 1

    cd ../.. || exit 1
}

dockerfile_init(){
    echo 'FROM scratch'                                                                         | tee Dockerfile
    echo 'COPY nautilus/rootfs/ /'                                                              | tee -a Dockerfile
    echo 'ENV USER=root'                                                                        | tee -a Dockerfile
    #beszel ports
    echo 'EXPOSE 8090'                                                                          | tee -a Dockerfile
    echo 'EXPOSE 45876'                                                                         | tee -a Dockerfile
    #nginx port
    echo 'EXPOSE 80'                                                                            | tee -a Dockerfile
    #echo 'SHELL ["/bin/sh", "-c"]'                                                             | tee -a Dockerfile
    echo 'ENTRYPOINT ["/init.sh"]'                                                              | tee -a Dockerfile
}

function create_init_file_agent() {
    echo -e "${YELLOW}create_init_file${RESET}"
    INIT_FILE="${ROOTFS_DIR}/init.sh"

    echo '#!/bin/sh'                                                        | tee    "$INIT_FILE" > /dev/null
    echo ''                                                                 | tee -a "$INIT_FILE" > /dev/null
    echo 'echo "Starting nginx..."'                                         | tee -a "$INIT_FILE" > /dev/null
    echo '/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf'  | tee -a "$INIT_FILE" > /dev/null 
    echo ''                                                                 | tee -a "$INIT_FILE" > /dev/null
    echo 'echo "Starting beszel-agent..."'                                  | tee -a "$INIT_FILE" > /dev/null
    echo '/usr/local/bin/beszel-agent &'                                    | tee -a "$INIT_FILE" > /dev/null
    echo '# Keep container running'                                         | tee -a "$INIT_FILE" > /dev/null
    echo 'tail -f /dev/null'                                                | tee -a "$INIT_FILE" > /dev/null

    chmod +x "$INIT_FILE"
}

function create_init_file_master() {
    echo -e "${YELLOW}create_init_file${RESET}"
    INIT_FILE="${ROOTFS_DIR}/init.sh"

    echo '#!/bin/sh'                                                                | tee    "$INIT_FILE" > /dev/null
    echo 'wget https://curl.haxx.se/ca/cacert.pem -O /etc/ssl/certs/ca-certificates.crt' | tee -a "$INIT_FILE" > /dev/null
    echo ''                                                                         | tee -a "$INIT_FILE" > /dev/null
    echo 'echo "Starting nginx..."'                                                 | tee -a "$INIT_FILE" > /dev/null
    echo '/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf'          | tee -a "$INIT_FILE" > /dev/null 
    echo ''                                                                         | tee -a "$INIT_FILE" > /dev/null
    echo 'echo "Starting beszel-agent..."'                                          | tee -a "$INIT_FILE" > /dev/null
    echo 'KEY_FILE=/beszel_data/id_ed25519.pub /usr/local/bin/beszel-agent &'       | tee -a "$INIT_FILE" > /dev/null
    echo ''                                                                         | tee -a "$INIT_FILE" > /dev/null
    echo 'echo "Starting beszel..."'                                                | tee -a "$INIT_FILE" > /dev/null
    echo '/usr/local/bin/beszel serve --http 0.0.0.0:8090 &'                        | tee -a "$INIT_FILE" > /dev/null
    echo ''                                                                         | tee -a "$INIT_FILE" > /dev/null
    echo '# Keep container running'                                                 | tee -a "$INIT_FILE" > /dev/null
    echo 'tail -f /dev/null'                                                        | tee -a "$INIT_FILE" > /dev/null

    chmod +x "$INIT_FILE"
}
function generate_beszel_keys() {
    DIR="./beszel_data"
    ENV_FILE="./.env"
    
    mkdir -p "$DIR"
    
    PRIVATE_KEY="$DIR/id_ed25519"
    PUBLIC_KEY="$DIR/id_ed25519.pub"
    
    ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "beszel-agent-key"
    chmod 600 "$PRIVATE_KEY"
    
    echo "Keys generated in $DIR"
    cat "$PUBLIC_KEY"
    mkdir -p "$ROOTFS_DIR/beszel_data/"
    echo "$ROOTFS_DIR/beszel_data/$PUBLIC_KEY"
    pwd
    echo "$PRIVATE_KEY"
    echo "$PUBLIC_KEY"
    cp $PUBLIC_KEY "$ROOTFS_DIR/beszel_data"
    cp $PRIVATE_KEY "$ROOTFS_DIR/beszel_data"
    
}

function main(){
    #------------------------------
    setup_dirs
    create_configs
    compile_and_install_busybox
    get_and_install_nginx
    generate_beszel_keys
    get_and_install_beszel
    get_and_install_curl
    get_and_install_lua
    get_and_install_jq
    #------------------------------
    #create_init_file_agent
    create_init_file_master
    dockerfile_init


    #------------------------------
    #docker buildx build --platform linux/amd64 -t nautilus:amd64 --load .
    #docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus:amd64
    #docker save -o nautilus_amd64.tar nautilus:amd64
    #------------------------------
    #docker buildx build --platform linux/arm64 -t nautilus:aarch64 --load .
    #docker save -o nautilus_aarch64.tar nautilus:aarch64
    #docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus:aarch64
    #docker load -i nautilus_aarch64.tar
    #------------------------------
	#docker build -t nautilus . 
    #docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus bin/sh
    #------------------------------
    #docker run --rm -it --entrypoint /bin/sh -p 80:80 -p 8090:8090 -p 45876:45876 nautilus
    #------------------------------
}
main
#/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf -t
# export KEY_FILE=/etc/beszel/id_ed25519.pub
# /usr/local/bin/beszel serve --http 0.0.0.0:8090

