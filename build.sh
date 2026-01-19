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
    #generate_beszel_keys
    get_and_install_beszel
    get_and_install_curl
    #------------------------------
    #create_init_file_agent
    create_init_file_master
    dockerfile_init


    #------------------------------
    docker buildx build --platform linux/amd64 -t nautilus:amd64 --load .
    docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus:amd64
    docker save -o nautilus_amd64.tar nautilus:amd64
    #------------------------------
    #docker buildx build --platform linux/arm64 -t nautilus:aarch64 --load .
    #docker save -o nautilus_aarch64.tar nautilus:aarch64
    #docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus:aarch64
    #docker load -i nautilus_aarch64.tar
    #------------------------------
	docker build -t nautilus . 
    docker run -it --rm -p 80:80 -p 8090:8090 -p 45876:45876 nautilus bin/sh
    #------------------------------
}
main
#/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf -t
# export KEY_FILE=/etc/beszel/id_ed25519.pub
# /usr/local/bin/beszel serve --http 0.0.0.0:8090

