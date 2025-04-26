SYSTEM_VERSION = 0.2.0
DISTRO_DIR = nautilus
ROOTFS_DIR = $(DISTRO_DIR)/rootfs

RED    := \033[1;31m
GREEN  := \033[1;32m
YELLOW := \033[1;33m
BLUE   := \033[1;34m
RESET  := \033[0m

.PHONY: help all setup_dirs create_configs install_busybox install_curl build_container run_container

help:
	@printf "$(BLUE)Available commands:$(RESET)\n"
	@printf "  $(GREEN)make run_container$(RESET)			- Run the Docker container\n"
	@printf "  $(GREEN)make build_container$(RESET)			- Build the Docker image\n"
	@printf "  ├ $(YELLOW)make setup_dirs$(RESET)			- Create essential system directories\n"
	@printf "  ├ $(YELLOW)make create_configs$(RESET)			- Create configuration files\n"
	@printf "  ├ $(YELLOW)make install_busybox$(RESET)		- Download and install BusyBox\n"
	@printf "  ├ $(YELLOW)make install_curl$(RESET)			- Download and install static cURL\n"
	@printf "  ├ $(YELLOW)make install_musl_gcc$(RESET)		- Download and install static musl-gcc toolchain\n"
	@printf "  └ $(YELLOW)make install_make$(RESET)			- Download and install static make\n"


all: help

setup_dirs:
	@printf "$(YELLOW)--- setup_dirs ---$(RESET)\n"
	mkdir -p $(ROOTFS_DIR)/{dev,proc,sys,bin,tmp,root,etc/ssl/certs}

create_configs:
	@printf "$(YELLOW)--- create_configs ---$(RESET)\n"
	touch $(ROOTFS_DIR)/etc/group
	touch $(ROOTFS_DIR)/etc/passwd
	echo "export SSL_CERT_DIR=/etc/ssl/certs" > $(ROOTFS_DIR)/etc/profile
	echo "NAME=\"Nautilus\"" > $(ROOTFS_DIR)/etc/os-release
	echo "VERSION=\"$(SYSTEM_VERSION)\"" >> $(ROOTFS_DIR)/etc/os-release
	echo "ID=nautilus" >> $(ROOTFS_DIR)/etc/os-release
	echo "PRETTY_NAME=\"Nautilus $(SYSTEM_VERSION)⚓\"" >> $(ROOTFS_DIR)/etc/os-release

install_busybox:
	@printf "$(YELLOW)--- install_busybox ---$(RESET)\n"
	wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox -O busybox
	chmod +x busybox
	mv busybox $(ROOTFS_DIR)/bin/busybox
	cd $(ROOTFS_DIR)/bin && for prog in $$(./busybox --list); do ln -sf /bin/busybox $$prog; done

install_curl:
	@printf "$(YELLOW)--- install_curl ---$(RESET)\n"
	wget https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64 -O curl
	chmod +x curl
	mv curl $(ROOTFS_DIR)/bin/curl

install_musl_gcc:
	@printf "$(YELLOW)--- install_musl_gcc ---$(RESET)\n"
	wget https://musl.cc/x86_64-linux-musl-cross.tgz
	tar -xzf x86_64-linux-musl-cross.tgz
	mv x86_64-linux-musl-cross/bin/x86_64-linux-musl-gcc $(ROOTFS_DIR)/bin/gcc
	rm -rf x86_64-linux-musl-cross x86_64-linux-musl-cross.tgz

install_make:
	@printf "$(YELLOW)--- install_make ---$(RESET)\n"
	wget https://ftp.gnu.org/gnu/make/make-4.4.tar.gz
	tar -xzf make-4.4.tar.gz 
	cd make-4.4 && ./configure LDFLAGS=-static
	cd make-4.4 && make
	mv make-4.4/make $(ROOTFS_DIR)/bin/make
	rm -rf make-4.4 make-4.4.tar.gz*

build_container: setup_dirs create_configs install_busybox install_curl install_musl_gcc install_make
	@printf "$(GREEN)--- build_container ---$(RESET)\n"
	docker build -t nautilus .

run_container:
	@printf "$(GREEN)--- run_container ---$(RESET)\n"
	docker run -it nautilus bin/sh
