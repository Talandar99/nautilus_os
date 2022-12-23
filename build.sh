#!/bin/bash

mkdir -p src
cd src
	wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz
	wget https://busybox.net/downloads/busybox-1.35.0.tar.bz2
	tar -xf linux-6.1.1.tar.xz
	tar -xf busybox-1.35.0.tar.bz2

	cd linux-6.1.1
		make defconfig
		make -j8 || exit
	cd ..

	cd busybox-1.35.0
		make defconfig
		sed 's/^.CONFIG_STATIC[^_].*$/CONFIG_STATIC=y/g' -i .config
		make CC=musl -j8 || exit
	cd ..
	
cd ..

cp /src/linux-6.1.1/arch/x86_64/boot/bzImage ./

mkdir initrd
cd initrd
	mkdir -p bin dev proc sys
	
	cd bin
	cd ../../src/busybox-1.35.0/bussybox ./

	for prog in $(./bussybox --list); do
		ln -s /bin/bussybox ./$prog
	done

	cd ..

	echo '#!/bin/bash' > init
	echo 'mount -t sysfs sysfs /sys' >> init
	echo 'mount -t proc proc /proc' >> init
	echo 'mount -t devtmpfs udev /dev' >> init
	echo 'sysctl -w kernel.printk="2 4 1 7"' >> init
	echo '/bin/sh' >> init
	
	chmod -R 777 .

	find . | cpio -o -H newc > ../initrd.img
cd ..


