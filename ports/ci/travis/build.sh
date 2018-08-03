#!/bin/bash

EXEC="docker exec ${DOCKERSYS}"
DRIVER_FILE=akvcam.ko
BUILDSCRIPT=dockerbuild.sh
system_image=system-image.img
system_mount_point=system-mount-point

cat << EOF >> ${BUILDSCRIPT}
echo "Available kernel headers:"
echo
ls /usr/src | grep linux-headers- | sort
echo
echo "Available kernel images:"
echo
ls /boot/vmlinuz-* | sort
echo
echo "Available QEMU images:"
echo
ls /usr/bin/qemu-system-* | sort
echo

# Build the driver and show it's info.
cd src
make KERNEL_DIR=/usr/src/linux-headers-${KERNEL_VERSION}-generic
cd ..
echo
echo "Driver info:"
echo
modinfo src/${DRIVER_FILE}
echo

# Create the system image to boot with QEMU.
qemu-img create ${system_image} 1g
mkfs.ext4 ${system_image}

# Install bootstrap system
mkdir ${system_mount_point}
mount -o loop ${system_image} ${system_mount_point}
debootstrap --arch amd64 xenial ${system_mount_point}

# Configure auto login with root user
sed -i 's/#NAutoVTs=6/NAutoVTs=1/' ${system_mount_point}/etc/systemd/logind.conf
sed -i 's/root:.:/root::/' ${system_mount_point}/etc/shadow

mkdir -p ${system_mount_point}/etc/systemd/system/getty@tty1.service.d
echo '[Service]' >> ${system_mount_point}/etc/systemd/system/getty@tty1.service.d/autologin.conf
echo 'ExecStart=' >> ${system_mount_point}/etc/systemd/system/getty@tty1.service.d/autologin.conf
echo 'ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM' >> ${system_mount_point}/etc/systemd/system/getty@tty1.service.d/autologin.conf

mkdir -p ${system_mount_point}/etc/systemd/system/serial-getty@ttyS0.service.d
echo '[Service]' >> ${system_mount_point}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
echo 'ExecStart=' >> ${system_mount_point}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
echo 'ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 %I \$TERM' >> ${system_mount_point}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf

mkdir -p ${system_mount_point}/etc/systemd/system/console-getty@tty1.service.d
echo '[Service]' >> ${system_mount_point}/etc/systemd/system/console-getty@tty1.service.d/autologin.conf
echo 'ExecStart=' >> ${system_mount_point}/etc/systemd/system/console-getty@tty1.service.d/autologin.conf
echo 'ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud console 115200,38400,9600 %I \$TERM' >> ${system_mount_point}/etc/systemd/system/console-getty@tty1.service.d/autologin.conf

# Prepare the system to test the driver
cp -vf src/${DRIVER_FILE} ${system_mount_point}/root
echo './driver_test.sh' >> ${system_mount_point}/root/.profile
touch ${system_mount_point}/root/driver_test.sh
chmod +x ${system_mount_point}/root/driver_test.sh
echo 'dmesg -C' >> ${system_mount_point}/root/driver_test.sh
echo 'insmod ${DRIVER_FILE}' >> ${system_mount_point}/root/driver_test.sh
echo 'dmesg' >> ${system_mount_point}/root/driver_test.sh
echo 'shutdown -h now' >> ${system_mount_point}/root/driver_test.sh
umount ${system_mount_point}

echo
echo "Booting system with custom kernel:"
echo
qemu-system-x86_64 \\
    -kernel /boot/vmlinuz-${KERNEL_VERSION}-generic \\
    -append "root=/dev/sda console=ttyS0,9600" \\
    -drive ${system_image},index=0,media=disk,format=raw \\
    --nographic
EOF
${EXEC} bash ${BUILDSCRIPT}
