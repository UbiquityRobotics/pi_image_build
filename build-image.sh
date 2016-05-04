#!/usr/bin/env bash

########################################################################
#
# Copyright (C) 2015 Martin Wimpress <code@ubuntu-mate.org>
# Copyright (C) 2015 Rohith Madhavan <rohithmadhavan@gmail.com>
# Copyright (C) 2015 Ryan Finnie <ryan@finnie.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
########################################################################

set -ex

if [ -f build-settings.sh ]; then
    source build-settings.sh
else
    echo "ERROR! Could not source build-settings.sh."
    exit 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "ERROR! Must be root."
    exit 1
fi

# Mount host system
function mount_system() {
    # In case this is a re-run move the cofi preload out of the way
    if [ -e $R/etc/ld.so.preload ]; then
        mv -v $R/etc/ld.so.preload $R/etc/ld.so.preload.disabled
    fi
    mount -t proc none $R/proc
    mount -t sysfs none $R/sys
    mount -o bind /dev $R/dev
    mount -o bind /dev/pts $R/dev/pts
    echo "nameserver 8.8.8.8" > $R/etc/resolv.conf
}

# Unmount host system
function umount_system() {
    umount -l $R/sys
    umount -l $R/proc
    umount -l $R/dev/pts
    umount -l $R/dev
    echo "" > $R/etc/resolv.conf
}

function sync_to() {
    local TARGET="${1}"
    if [ ! -d "${TARGET}" ]; then
        mkdir -p "${TARGET}"
    fi
    rsync -a --progress --delete ${R}/ ${TARGET}/
}

# Base debootstrap
function bootstrap() {
    # Required tools
    apt-get -y install binfmt-support debootstrap f2fs-tools \
    qemu-user-static rsync ubuntu-keyring wget whois

    # Use the same base system for all flavours.
    if [ ! -f "${R}/tmp/.bootstrap" ]; then
        if [ "${ARCH}" == "armv7l" ]; then
            debootstrap --verbose $RELEASE $R http://ports.ubuntu.com/
        else
            qemu-debootstrap --verbose --arch=armhf $RELEASE $R http://ports.ubuntu.com/
        fi
        touch "$R/tmp/.bootstrap"
    fi
}

function generate_locale() {
    for LOCALE in $(chroot $R locale | cut -d'=' -f2 | grep -v : | sed 's/"//g' | uniq); do
        if [ -n "${LOCALE}" ]; then
            chroot $R locale-gen $LOCALE
        fi
    done
}

# Set up initial sources.list
function apt_sources() {
    cat <<EOM >$R/etc/apt/sources.list
deb http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
EOM
}

function apt_upgrade() {
    chroot $R apt-get update
    chroot $R apt-get -y -u dist-upgrade
}

function apt_clean() {
    chroot $R apt-get -y autoremove
    chroot $R apt-get clean
}

# Install Ubuntu minimal
function ubuntu_minimal() {
    chroot $R apt-get -y install f2fs-tools software-properties-common
    if [ ! -f "${R}/tmp/.minimal" ]; then
        chroot $R apt-get -y install ubuntu-minimal
        touch "${R}/tmp/.minimal"
    fi
}

# Install Ubuntu minimal
function ubuntu_standard() {
    if [ "${FLAVOUR}" != "ubuntu-minimal" ] && [ ! -f "${R}/tmp/.standard" ]; then
        chroot $R apt-get -y install ubuntu-standard
        touch "${R}/tmp/.standard"
    fi
}

# Install meta packages
function install_meta() {
    local META="${1}"
    local RECOMMENDS="${2}"
    if [ "${RECOMMENDS}" == "--no-install-recommends" ]; then
        echo 'APT::Install-Recommends "false";' > $R/etc/apt/apt.conf.d/99noinstallrecommends
    else
        local RECOMMENDS=""
    fi

    cat <<EOM >$R/usr/local/bin/${1}.sh
#!/bin/bash
service dbus start
apt-get -f install
dpkg --configure -a
apt-get -y install ${RECOMMENDS} ${META}^
service dbus stop
EOM
    chmod +x $R/usr/local/bin/${1}.sh
    chroot $R /usr/local/bin/${1}.sh

    rm $R/usr/local/bin/${1}.sh

    if [ "${RECOMMENDS}" == "--no-install-recommends" ]; then
        rm $R/etc/apt/apt.conf.d/99noinstallrecommends
    fi
}

function create_groups() {
    chroot $R groupadd -f --system gpio
    chroot $R groupadd -f --system i2c
    chroot $R groupadd -f --system input
    chroot $R groupadd -f --system spi

    # Create adduser hook
    cat <<'EOM' >$R/usr/local/sbin/adduser.local
#!/bin/sh
# This script is executed as the final step when calling `adduser`
# USAGE:
#   adduser.local USER UID GID HOME

# Add user to the Raspberry Pi specific groups
usermod -a -G adm,gpio,i2c,input,spi,video $1
EOM
    chmod +x $R/usr/local/sbin/adduser.local
}

# Create default user
function create_user() {
    local DATE=$(date +%m%H%M%S)
    local PASSWD=$(mkpasswd -m sha-512 ${USERNAME} ${DATE})

    if [ ${OEM_CONFIG} -eq 1 ]; then
        chroot $R addgroup --gid 29999 oem
        chroot $R adduser --gecos "OEM Configuration (temporary user)" --add_extra_groups --disabled-password --gid 29999 --uid 29999 ${USERNAME}
    else
        chroot $R adduser --gecos "${FLAVOUR_NAME}" --add_extra_groups --disabled-password ${USERNAME}
    fi
    chroot $R usermod -a -G sudo -p ${PASSWD} ${USERNAME}
}

# Prepare oem-config for first boot.
function prepare_oem_config() {
    if [ ${OEM_CONFIG} -eq 1 ]; then
        if [ "${FLAVOUR}" == "kubuntu" ]; then
            chroot $R apt-get -y install --no-install-recommends oem-config-kde ubiquity-frontend-kde ubiquity-ubuntu-artwork
        else
            chroot $R apt-get -y install --no-install-recommends oem-config-gtk ubiquity-frontend-gtk ubiquity-ubuntu-artwork
        fi

        if [ "${FLAVOUR}" == "ubuntu" ]; then
            chroot $R apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu
        elif [ "${FLAVOUR}" == "ubuntu-mate" ]; then
            chroot $R apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu-mate
            # Force the slideshow to use Ubuntu MATE artwork.
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/lib/ubiquity/plugins/ubi-usersetup.py
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/sbin/oem-config-remove-gtk
        fi
        cp -a $R/usr/lib/oem-config/oem-config.service $R/lib/systemd/system
        cp -a $R/usr/lib/oem-config/oem-config.target $R/lib/systemd/system
        chroot $R /bin/systemctl enable oem-config.service
        chroot $R /bin/systemctl enable oem-config.target
        chroot $R /bin/systemctl set-default oem-config.target
    fi
}

function configure_ssh() {
    chroot $R apt-get -y install openssh-server
    cat > $R/etc/systemd/system/sshdgenkeys.service << EOF
[Unit]
Description=SSH key generation on first startup
Before=ssh.service
ConditionPathExists=|!/etc/ssh/ssh_host_key
ConditionPathExists=|!/etc/ssh/ssh_host_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key.pub

[Service]
ExecStart=/usr/bin/ssh-keygen -A
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=ssh.service
EOF

    mkdir -p $R/etc/systemd/system/ssh.service.wants
    chroot $R ln -s /etc/systemd/system/sshdgenkeys.service /etc/systemd/system/ssh.service.wants
}

function configure_network() {
    # Set up hosts
    echo ${FLAVOUR} >$R/etc/hostname
    cat <<EOM >$R/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       ${FLAVOUR}
EOM

    # Set up interfaces
    if [ "${FLAVOUR}" != "ubuntu-minimal" ] && [ "${FLAVOUR}" != "ubuntu-standard" ]; then
        cat <<EOM >$R/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# The loopback network interface
auto lo
iface lo inet loopback
EOM
    else
        cat <<EOM >$R/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOM
    fi
}

function configure_hardware() {
    local FS="${1}"
    if [ "${FS}" != "ext4" ] && [ "${FS}" != 'f2fs' ]; then
        echo "ERROR! Unsupport filesystem requested. Exitting."
        exit 1
    fi

    chroot $R apt-get -y update

    # gdebi-core used for installing copies-and-fills and omxplayer
    chroot $R apt-get -y install gdebi-core
    local COFI="http://archive.raspberrypi.org/debian/pool/main/r/raspi-copies-and-fills/raspi-copies-and-fills_0.5-1_armhf.deb"

    # Install the RPi PPA
    chroot $R apt-add-repository -y ppa:ubuntu-pi-flavour-makers/ppa
    chroot $R apt-get update

    # Firmware Kernel installation
    chroot $R apt-get -y install libraspberrypi-bin libraspberrypi-dev \
    libraspberrypi-doc libraspberrypi0 raspberrypi-bootloader rpi-update
    chroot $R apt-get -y install bluez-firmware linux-firmware pi-bluetooth

    # Raspberry Pi 3 WiFi firmware. Package this?
    cp -v firmware/* $R/lib/firmware/brcm/
    chown root:root $R/lib/firmware/brcm/*

    if [ "${FLAVOUR}" != "ubuntu-minimal" ] && [ "${FLAVOUR}" != "ubuntu-standard" ]; then
        # Install fbturbo drivers on non composited desktop OS
        # fbturbo causes VC4 to fail
        if [ "${FLAVOUR}" == "lubuntu" ] || [ "${FLAVOUR}" == "ubuntu-mate" ] || [ "${FLAVOUR}" == "xubuntu" ]; then
            chroot $R apt-get -y install xserver-xorg-video-fbturbo
        fi

        # omxplayer
        local OMX="http://omxplayer.sconde.net/builds/omxplayer_0.3.7~git20160206~cb91001_armhf.deb"
        # - Requires: libpcre3 libfreetype6 fonts-freefont-ttf dbus libssl1.0.0 libsmbclient libssh-4
        wget -c "${OMX}" -O $R/tmp/omxplayer.deb
        chroot $R gdebi -n /tmp/omxplayer.deb

        # Make Ubiquity "compatible" with the Raspberry Pi Foundation kernel.
        if [ ${OEM_CONFIG} -eq 1 ]; then
            cp plugininstall-${RELEASE}.py $R/usr/share/ubiquity/plugininstall.py
        fi
    fi

    # Hardware - Create a fake HW clock and add rng-tools
    chroot $R apt-get -y install fake-hwclock fbset i2c-tools rng-tools

    # Install Raspberry Pi system tweaks
    chroot $R apt-get -y install raspberrypi-general-mods raspberrypi-sys-mods

    # Disable TLP
    if [ -f $R/etc/default/tlp ]; then
        sed -i s'/TLP_ENABLE=1/TLP_ENABLE=0/' $R/etc/default/tlp
    fi

    # copies-and-fills
    # Create /spindel_install so cofi doesn't segfault when chrooted via qemu-user-static
    touch $R/spindle_install
    wget -c "${COFI}" -O $R/tmp/cofi.deb
    chroot $R gdebi -n /tmp/cofi.deb

    # Set up fstab
    cat <<EOM >$R/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ${FS}   defaults,noatime  0       1
/dev/mmcblk0p1  /boot/          vfat    defaults          0       2
EOM

    # Set up firmware config
    if [ "${FLAVOUR}" == "ubuntu-minimal" ] || [ "${FLAVOUR}" == "ubuntu-standard" ]; then
        echo "net.ifnames=0 biosdevname=0 dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FS} elevator=deadline rootwait quiet splash" > $R/boot/cmdline.txt
    else
        echo "dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FS} elevator=deadline rootwait quiet splash" > $R/boot/cmdline.txt
        sed -i 's/#framebuffer_depth=16/framebuffer_depth=32/' $R/boot/config.txt
        #sed -i 's/#framebuffer_ignore_alpha=0/framebuffer_ignore_alpha=1/' $R/boot/config.txt
        sed -i 's/#dtparam=audio=off/dtparam=audio=on/' $R/boot/config.txt

        # Enable VC4 on composited desktops
        if [ "${FLAVOUR}" == "kubuntu" ] || [ "${FLAVOUR}" == "ubuntu" ] || [ "${FLAVOUR}" == "ubuntu-gnome" ]; then
            echo "dtoverlay=vc4-kms-v3d" > $R/boot/config.txt
        fi
    fi

    # Save the clock
    chroot $R fake-hwclock save
}

function install_software() {
    local SCRATCH="http://archive.raspberrypi.org/debian/pool/main/s/scratch/scratch_1.4.20131203-2_all.deb"
    local WIRINGPI="http://archive.raspberrypi.org/debian/pool/main/w/wiringpi/wiringpi_2.32_armhf.deb"

    if [ "${FLAVOUR}" != "ubuntu-minimal" ]; then
        # Python
        chroot $R apt-get -y install python-minimal python3-minimal
        chroot $R apt-get -y install python-dev python3-dev
        chroot $R apt-get -y install python-pip python3-pip
        chroot $R apt-get -y install python-setuptools python3-setuptools

        # Python extras a Raspberry Pi hacker expects to have available ;-)
        chroot $R apt-get -y install raspi-gpio
        chroot $R apt-get -y install python-rpi.gpio python3-rpi.gpio
        chroot $R apt-get -y install python-serial python3-serial
        chroot $R apt-get -y install python-spidev python3-spidev
        chroot $R apt-get -y install python-picamera python3-picamera
        chroot $R apt-get -y install python-rtimulib python3-rtimulib
        chroot $R apt-get -y install python-sense-hat python3-sense-hat
        chroot $R apt-get -y install python-astropi python3-astropi
        chroot $R apt-get -y install python-pil python3-pil
        chroot $R apt-get -y install python-gpiozero python3-gpiozero
        chroot $R apt-get -y install python-pygame
        chroot $R pip2 install codebug_tether
        chroot $R pip3 install codebug_tether
    fi

    if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        # Install the Minecraft PPA
        chroot $R apt-add-repository -y ppa:flexiondotorg/minecraft
        chroot $R apt-add-repository -y ppa:ubuntu-mate-dev/welcome
        chroot $R apt-get update

        # Python IDLE
        chroot $R apt-get -y install idle idle3

        # YouTube DL
        chroot $R apt-get -y install ffmpeg rtmpdump
        chroot $R apt-get -y --no-install-recommends install ffmpeg youtube-dl
        chroot $R apt-get -y install youtube-dlg

        # Scratch (nuscratch)
        # - Requires: scratch wiringpi
        wget -c "${WIRINGPI}" -O $R/tmp/wiringpi.deb
        chroot $R gdebi -n /tmp/wiringpi.deb
        wget -c "${SCRATCH}" -O $R/tmp/scratch.deb
        chroot $R gdebi -n /tmp/scratch.deb
        chroot $R apt-get -y install nuscratch

        # Minecraft
        chroot $R apt-get -y install minecraft-pi python-picraft python3-picraft

        # Sonic Pi
        chroot $R apt-get -y install sonic-pi=2.9.0~repack-6

        # raspi-config - Needs forking/modifying to support Ubuntu
        # chroot $R apt-get -y install raspi-config
    fi
}

function clean_up() {
    rm -f $R/etc/apt/*.save || true
    rm -f $R/etc/apt/sources.list.d/*.save || true
    rm -f $R/etc/resolvconf/resolv.conf.d/original
    rm -f $R/run/*/*pid || true
    rm -f $R/run/*pid || true
    rm -f $R/run/cups/cups.sock || true
    rm -f $R/run/uuidd/request || true
    rm -f $R/etc/*-
    rm -rf $R/tmp/*
    rm -f $R/var/crash/*
    rm -f $R/var/lib/urandom/random-seed

    # Build cruft
    rm -f $R/var/cache/debconf/*-old || true
    rm -f $R/var/lib/dpkg/*-old || true
    rm -f $R/var/cache/bootstrap.log || true
    truncate -s 0 $R/var/log/lastlog || true
    truncate -s 0 $R/var/log/faillog || true

    # SSH host keys
    rm -f $R/etc/ssh/ssh_host_*key
    rm -f $R/etc/ssh/ssh_host_*.pub

    # Clean up old Raspberry Pi firmware and modules
    rm -f $R/boot/.firmware_revision || true
    rm -rf $R/boot.bak || true
    rm -rf $R/lib/modules.bak || true
    # Old kernel modules
    #rm -rf $R/lib/modules/4.1.19* || true

    # Potentially sensitive.
    rm -f $R/root/.bash_history
    rm -f $R/root/.ssh/known_hosts

    # Remove bogus home directory
    rm -rf $R/home/${SUDO_USER} || true

    # Machine-specific, so remove in case this system is going to be
    # cloned.  These will be regenerated on the first boot.
    rm -f $R/etc/udev/rules.d/70-persistent-cd.rules
    rm -f $R/etc/udev/rules.d/70-persistent-net.rules
    rm -f $R/etc/NetworkManager/system-connections/*
    [ -L $R/var/lib/dbus/machine-id ] || rm -f $R/var/lib/dbus/machine-id
    echo '' > $R/etc/machine-id

    # Enable cofi
    if [ -e $R/etc/ld.so.preload.disabled ]; then
        mv -v $R/etc/ld.so.preload.disabled $R/etc/ld.so.preload
    fi

    rm -rf $R/tmp/.bootstrap || true
    rm -rf $R/tmp/.minimal || true
    rm -rf $R/tmp/.standard || true
}

function make_raspi2_image() {
    # Build the image file
    local FS="${1}"
    local GB=${2}

    if [ "${FS}" != "ext4" ] && [ "${FS}" != 'f2fs' ]; then
        echo "ERROR! Unsupport filesystem requested. Exitting."
        exit 1
    fi

    if [ ${GB} -ne 4 ] && [ ${GB} -ne 8 ] && [ ${GB} -ne 16 ]; then
        echo "ERROR! Unsupport card image size requested. Exitting."
        exit 1
    fi

    if [ ${GB} -eq 4 ]; then
        SEEK=3750
        SIZE=7546880
        SIZE_LIMIT=3685
    elif [ ${GB} -eq 8 ]; then
        SEEK=7680
        SIZE=15728639
        SIZE_LIMIT=7615
    elif [ ${GB} -eq 16 ]; then
        SEEK=15360
        SIZE=31457278
        SIZE_LIMIT=15230
    fi

    # If a compress version exists, remove it.
    rm -f "${BASEDIR}/${IMAGE}.bz2" || true

    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=1
    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=0 seek=${SEEK}

    sfdisk -f "$BASEDIR/${IMAGE}" <<EOM
unit: sectors

1 : start=     2048, size=   131072, Id= c, bootable
2 : start=   133120, size=  ${SIZE}, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM

    BOOT_LOOP="$(losetup -o 1M --sizelimit 64M -f --show ${BASEDIR}/${IMAGE})"
    ROOT_LOOP="$(losetup -o 65M --sizelimit ${SIZE_LIMIT}M -f --show ${BASEDIR}/${IMAGE})"
    mkfs.vfat -n PI_BOOT -S 512 -s 16 -v "${BOOT_LOOP}"
    if [ "${FS}" == "ext4" ]; then
        mkfs.ext4 -L PI_ROOT -m 0 "${ROOT_LOOP}"
    else
        mkfs.f2fs -l PI_ROOT -o 1 "${ROOT_LOOP}"
    fi
    MOUNTDIR="${BUILDDIR}/mount"
    mkdir -p "${MOUNTDIR}"
    mount "${ROOT_LOOP}" "${MOUNTDIR}"
    mkdir -p "${MOUNTDIR}/boot"
    mount "${BOOT_LOOP}" "${MOUNTDIR}/boot"
    rsync -a --progress "$R/" "${MOUNTDIR}/"
    umount -l "${MOUNTDIR}/boot"
    umount -l "${MOUNTDIR}"
    fsck -y "${BOOT_LOOP}"
    fsck -y "${ROOT_LOOP}"
    tune2fs -c 0 -i 0 "${ROOT_LOOP}"
    losetup -d "${ROOT_LOOP}"
    losetup -d "${BOOT_LOOP}"
}

function make_tarball() {
    if [ ${MAKE_TARBALL} -eq 1 ]; then
        rm -f "${BASEDIR}/${TARBALL}" || true
        tar -cSf "${BASEDIR}/${TARBALL}" $R
    fi
}

function stage_01_base() {
    R="${BASE_R}"
    bootstrap
    mount_system
    generate_locale
    apt_sources
    apt_upgrade
    ubuntu_minimal
    ubuntu_standard
    apt_clean
    umount_system
    sync_to "${DESKTOP_R}"
}

function stage_02_desktop() {
    R="${DESKTOP_R}"
    mount_system

    if [ "${FLAVOUR}" == "ubuntu-minimal" ] || [ "${FLAVOUR}" == "ubuntu-standard" ]; then
        echo "Skipping desktop install for ${FLAVOUR}"
    elif [ "${FLAVOUR}" == "lubuntu" ] || [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        install_meta ${FLAVOUR}-core --no-install-recommends
        install_meta ${FLAVOUR}-desktop --no-install-recommends
    elif [ "${FLAVOUR}" == "xubuntu" ]; then
        install_meta ${FLAVOUR}-core
        install_meta ${FLAVOUR}-desktop
    else
        install_meta ${FLAVOUR}-desktop
    fi

    create_groups
    create_user
    prepare_oem_config
    configure_ssh
    configure_network
    apt_upgrade
    apt_clean
    umount_system
    clean_up
    sync_to ${DEVICE_R}
    make_tarball
}

function stage_03_raspi2() {
    R=${DEVICE_R}
    mount_system
    configure_hardware ${FS_TYPE}
    install_software
    apt_upgrade
    apt_clean
    clean_up
    umount_system
    make_raspi2_image ${FS_TYPE} ${FS_SIZE}
}

function stage_04_corrections() {
    R=${DEVICE_R}
    mount_system

    #Insert corrections here.

    apt_clean
    clean_up
    umount_system
    make_raspi2_image ${FS_TYPE} ${FS_SIZE}
}

stage_01_base
stage_02_desktop
stage_03_raspi2
#stage_04_corrections
