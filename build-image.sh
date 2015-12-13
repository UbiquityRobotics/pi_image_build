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
        mv -v $R/etc/ld.so.preload $R/etc/ld.so.preload.disable
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

    cat <<EOM >$R/etc/apt/apt.conf.d/50raspi
# Never use pdiffs, current implementation is very slow on low-powered devices
Acquire::PDiffs "0";
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

        if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
            chroot $R apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu-mate
            # Force the slideshow to use Ubuntu MATE artwork.
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/lib/ubiquity/plugins/ubi-usersetup.py
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/sbin/oem-config-remove-gtk
        fi
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

function add_scripts() {
    if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        cat <<'EOF' >$R/usr/local/bin/graphical
#!/usr/bin/env bash
# Call with either enable or disable as first parameter

if [ $(id -u) -ne 0 ]; then
    echo "ERROR! $(basename $) must be run as 'root'."
    exit 1
fi

if [ "$1" == "enable" ]; then
    systemctl set-default graphical.target
elif [ "$1" == "disable" ]; then
    systemctl set-default multi-user.target
else
    echo "$(basename $0) should be invoked with with either 'enable' or 'disable' as first parameter."
fi
EOF
        chmod +x $R/usr/local/bin/graphical
    fi
}

function configure_hardware() {
    # Ported
    # http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/raspberrypi-firmware_1.20151118-1.dsc # Foundation's Kernel
    # https://launchpad.net/~fo0bar/+archive/ubuntu/rpi2-nightly/+files/xserver-xorg-video-fbturbo_0%7Egit.20151007.f9a6ed7-0%7Enightly.dsc

    # Kernel and Firmware - Pending
    # https://twolife.be/raspbian/pool/main/bcm-videocore-pkgconfig/bcm-videocore-pkgconfig_1.dsc    
    # https://twolife.be/raspbian/pool/main/linux/linux_4.1.8-1+rpi1.dsc
    # http://archive.raspberrypi.org/debian/pool/main/r/raspi-copies-and-fills/raspi-copies-and-fills_0.5-1.dsc # FTBFS in a PPA

    local FS="${1}"
    if [ "${FS}" != "ext4" ] && [ "${FS}" != 'f2fs' ]; then
        echo "ERROR! Unsupport filesystem requested. Exitting."
        exit 1
    fi

    # gdebi-core used for installing copies-and-fills and omxplayer
    chroot $R apt-get -y install gdebi-core
    local COFI="http://archive.raspberrypi.org/debian/pool/main/r/raspi-copies-and-fills/raspi-copies-and-fills_0.5-1_armhf.deb"

    # Install the RPi PPA
    chroot $R apt-add-repository -y ppa:ubuntu-pi-flavour-makers/ppa
    chroot $R apt-get update

    # Firmware Kernel installation
    chroot $R apt-get -y install libraspberrypi-bin libraspberrypi-dev \
    libraspberrypi-doc libraspberrypi0 raspberrypi-bootloader rpi-update
    chroot $R apt-get -y install linux-firmware linux-firmware-nonfree
    chroot $R rpi-update

    # Add VideoCore libs to ld.so
    echo "/opt/vc/lib" > $R/etc/ld.so.conf.d/vmcs.conf

    if [ "${FLAVOUR}" != "ubuntu-minimal" ] && [ "${FLAVOUR}" != "ubuntu-standard" ]; then
        # Install X drivers
        chroot $R apt-get -y install xserver-xorg-video-fbturbo
        cat <<EOM >$R/etc/X11/xorg.conf
Section "Device"
    Identifier "Raspberry Pi FBDEV"
    Driver "fbturbo"
    Option "fbdev" "/dev/fb0"
    Option "SwapbuffersWait" "true"
EndSection
EOM
        # omxplayer
        local OMX="http://omxplayer.sconde.net/builds/omxplayer_0.3.6~git20150912~d99bd86_armhf.deb"
        # - Requires: libpcre3 libfreetype6 fonts-freefont-ttf dbus libssl1.0.0 libsmbclient libssh-4
        wget -c "${OMX}" -O $R/tmp/omxplayer.deb
        chroot $R gdebi -n /tmp/omxplayer.deb

        # Make Ubiquity "compatible" with the Raspberry Pi 2 kernel.
        if [ ${OEM_CONFIG} -eq 1 ]; then
            #sed -i 's/self\.remove_unusable_kernels()/#self\.remove_unusable_kernels()/' $R/usr/share/ubiquity/plugininstall.py
            #sed -i "s/\['linux-image-' + self.kernel_version,/\['/" $R/usr/share/ubiquity/plugininstall.py
            cp plugininstall-pi.py $R/usr/share/ubiquity/plugininstall.py
        fi
    fi

    # Hardware - Create a fake HW clock and add rng-tools
    chroot $R apt-get -y install fake-hwclock fbset i2c-tools rng-tools

    # Load sound module on boot and enable HW random number generator
    cat <<EOM >$R/etc/modules-load.d/rpi2.conf
snd_bcm2835
bcm2708_rng
EOM

    # Blacklist platform modules not applicable to the RPi2
    cat <<EOM >$R/etc/modprobe.d/blacklist-rpi2.conf
blacklist snd_soc_pcm512x_i2c
blacklist snd_soc_pcm512x
blacklist snd_soc_tas5713
blacklist snd_soc_wm8804
EOM

    # Disable TLP
    if [ -f $R/etc/default/tlp ]; then
        sed -i s'/TLP_ENABLE=1/TLP_ENABLE=0/' $R/etc/default/tlp
    fi

    # udev rules
    printf 'SUBSYSTEM=="vchiq", GROUP="video", MODE="0660"\n' > $R/etc/udev/rules.d/10-local-rpi.rules
    printf "SUBSYSTEM==\"gpio*\", PROGRAM=\"/bin/sh -c 'chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio; chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio'\"\n" > $R/etc/udev/rules.d/99-com.rules
    printf 'SUBSYSTEM=="input", GROUP="input", MODE="0660"\n' >> $R/etc/udev/rules.d/99-com.rules
    printf 'SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"\n' >> $R/etc/udev/rules.d/99-com.rules
    printf 'SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"\n' >> $R/etc/udev/rules.d/99-com.rules
    cat <<EOF > $R/etc/udev/rules.d/40-scratch.rules
ATTRS{idVendor}=="0694", ATTRS{idProduct}=="0003", SUBSYSTEMS=="usb", ACTION=="add", MODE="0666", GROUP="plugdev"
EOF

    # copies-and-fills
    wget -c "${COFI}" -O $R/tmp/cofi.deb
    chroot $R gdebi -n /tmp/cofi.deb
    # Disabled cofi so it doesn't segfault when building via qemu-user-static
    mv -v $R/etc/ld.so.preload $R/etc/ld.so.preload.disable

    # Set up fstab
    cat <<EOM >$R/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ${FS}   defaults,noatime  0       1
/dev/mmcblk0p1  /boot/          vfat    defaults          0       2
EOM

    # Set up firmware config
    wget -c https://raw.githubusercontent.com/Evilpaul/RPi-config/master/config.txt -O $R/boot/config.txt
    if [ "${FLAVOUR}" == "ubuntu-minimal" ] || [ "${FLAVOUR}" == "ubuntu-standard" ]; then
        echo "net.ifnames=0 biosdevname=0 dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FS} elevator=deadline rootwait quiet splash" > $R/boot/cmdline.txt
    else
        echo "dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FS} elevator=deadline rootwait quiet splash" > $R/boot/cmdline.txt
        sed -i 's/#framebuffer_depth=16/framebuffer_depth=32/' $R/boot/config.txt
        sed -i 's/#framebuffer_ignore_alpha=0/framebuffer_ignore_alpha=1/' $R/boot/config.txt
    fi

    # Save the clock
    chroot $R fake-hwclock save
}

function install_software() {
    # https://archive.raspberrypi.org/debian/pool/main/m/minecraft-pi/minecraft-pi_0.1.1-4.dsc
    # http://archive.raspberrypi.org/debian/pool/main/r/raspi-gpio/raspi-gpio_0.20150914.dsc
    # http://archive.raspberrypi.org/debian/pool/main/s/sonic-pi/sonic-pi_2.7.0-1.dsc
    # http://archive.raspberrypi.org/debian/pool/main/p/picamera/picamera_1.10-1.dsc
    # http://archive.raspberrypi.org/debian/pool/main/n/nuscratch/nuscratch_20150916.dsc # Modify wrapper in debian/scratch to just be "sudo "
    # http://archive.raspberrypi.org/debian/pool/main/r/rtimulib/rtimulib_7.2.1-3.dsc
    # http://archive.raspberrypi.org/debian/pool/main/r/raspi-config/raspi-config_20151117.dsc
    # http://archive.raspberrypi.org/debian/pool/main/r/rpi.gpio/rpi.gpio_0.5.11-1+jessie.dsc # Hardcode target Python 3.x version in debian/rules
    # http://archive.raspberrypi.org/debian/pool/main/s/spidev/spidev_2.0~git20150907.dsc
    # http://archive.raspberrypi.org/debian/pool/main/c/codebug-tether/codebug-tether_0.4.3-1.dsc # Hardcode target Python 3.x in debian/rules
    # http://archive.raspberrypi.org/debian/pool/main/c/codebug-i2c-tether/codebug-i2c-tether_0.2.3-1.dsc # Hardcode target Python 3.x in debian/rules
    # http://archive.raspberrypi.org/debian/pool/main/c/compoundpi/compoundpi_0.4-1.dsc

    # FTBFS
    # http://archive.raspberrypi.org/debian/pool/main/g/gst-omx1.0/gst-omx1.0_1.0.0.1-0+rpi15.dsc
    # http://archive.raspberrypi.org/debian/pool/main/r/rc-gui/rc-gui_0.1-1.dsc

    # Pending
    # http://archive.raspberrypi.org/debian/pool/main/p/python-sense-hat/python-sense-hat_2.1.0-1.dsc # FTBFS
    # http://archive.raspberrypi.org/debian/pool/main/a/astropi/astropi_1.1.5-1.dsc # REQ Sense-hat
    # http://archive.raspberrypi.org/debian/pool/main/s/sense-hat/sense-hat_1.2.dsc # REQ python-sense-hat
    # http://archive.raspberrypi.org/debian/pool/main/p/pgzero/pgzero_1.0.2-1.dsc
    # https://archive.raspberrypi.org/debian/pool/main/e/epiphany-browser/epiphany-browser_3.8.2.0-0rpi23.dsc

    # Kodi - Pending
    # http://archive.ubuntu.com/ubuntu/pool/universe/a/afpfs-ng/afpfs-ng_0.8.1-5ubuntu1.dsc
    # http://archive.mene.za.net/raspbian/pool/unstable/k/kodi/kodi_15.1-1%7ejessie.dsc
    # https://twolife.be/raspbian/pool/main/kodi/kodi_15.1+dfsg1-2+rpi1.dsc # FTBFS
    # https://twolife.be/raspbian/pool/main/omxplayer/omxplayer_0.git20150303-1.dsc

    local NODERED="http://archive.raspberrypi.org/debian/pool/main/n/nodered/nodered_0.12.1_armhf.deb"
    local SCRATCH="http://archive.raspberrypi.org/debian/pool/main/s/scratch/scratch_1.4.20131203-2_all.deb"
    local WIRINGPI="http://archive.raspberrypi.org/debian/pool/main/w/wiringpi/wiringpi_2.24_armhf.deb"
    local SENSEHAT2="http://archive.raspberrypi.org/debian/pool/main/p/python-sense-hat/python-sense-hat_2.1.0-1_armhf.deb"
    local SENSEHAT3="http://archive.raspberrypi.org/debian/pool/main/p/python-sense-hat/python3-sense-hat_2.1.0-1_armhf.deb"
    local ASTROPI2="http://archive.raspberrypi.org/debian/pool/main/a/astropi/python-astropi_1.1.5-1_armhf.deb"
    local ASTROPI3="http://archive.raspberrypi.org/debian/pool/main/a/astropi/python3-astropi_1.1.5-1_armhf.deb"
    local TBOPLAYER_URL="https://raw.githubusercontent.com/KenT2/tboplayer/master/"

	if [ "${FLAVOUR}" == "ubuntu-minimal" ] || [ "${FLAVOUR}" == "ubuntu-standard" ] || [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        # Install the RPi PPA
        chroot $R apt-add-repository -y ppa:ubuntu-pi-flavour-makers/ppa
        chroot $R apt-get update

        # Python
        chroot $R apt-get -y install python-minimal python3-minimal
        chroot $R apt-get -y install python-dev python3-dev
        chroot $R apt-get -y install python-pip python3-pip
        chroot $R apt-get -y install idle idle3

        # Python extras a Raspberry Pi hacker expects to have available ;-)
        chroot $R apt-get -y install raspi-gpio
        chroot $R apt-get -y install python-rpi.gpio python3-rpi.gpio
        chroot $R apt-get -y install python-serial python3-serial
        chroot $R apt-get -y install python-spidev python3-spidev
        chroot $R apt-get -y install python-codebug-tether python3-codebug-tether
        chroot $R apt-get -y install python-codebug-i2c-tether python3-codebug-i2c-tether
        chroot $R apt-get -y install python-picamera python3-picamera
        chroot $R apt-get -y install python-rtimulib python3-rtimulib
        chroot $R apt-get -y install python-pil python3-pil
        chroot $R apt-get -y install python-pygame

        # Python Sense Hat
        wget -c "${SENSEHAT2}" -O $R/tmp/sensehat2.deb
        chroot $R gdebi -n /tmp/sensehat2.deb
        wget -c "${SENSEHAT3}" -O $R/tmp/sensehat3.deb
        chroot $R gdebi -n /tmp/sensehat3.deb

        # Astro Pi
        wget -c "${ASTROPI2}" -O $R/tmp/astropi2.deb
        chroot $R gdebi -n /tmp/astropi2.deb
        wget -c "${ASTROPI3}" -O $R/tmp/astropi3.deb
        chroot $R gdebi -n /tmp/astropi3.deb
	fi

    if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        # Install the Minecraft PPA
        chroot $R apt-add-repository -y ppa:flexiondotorg/minecraft
        chroot $R apt-get update

        # tboplayer
        chroot $R apt-get -y install ffmpeg youtube-dl youtube-dlg
        chroot $R apt-get -y install python-pexpect python3-pexpect
        chroot $R apt-get -y install python-ptyprocess python3-ptyprocess
        chroot $R apt-get -y install python-gobject-2 python-gobject
        chroot $R apt-get -y install python-tk python3-tk
        wget -c "${TBOPLAYER_URL}/tboplayer.py" -O $R/usr/local/bin/tboplayer.py
        wget -c "${TBOPLAYER_URL}/yt-dl_supported_sites" -O $R/usr/local/bin/yt-dl_supported_sites

        # Create a sane default tboplayer configuration
        mkdir -p $R/etc/skel/.tboplayer
        cat <<EOM >$R/etc/skel/.tboplayer/tboplayer.cfg
[config]
audio = hdmi
subtitles = off
mode = single
playlists =
tracks =
omx_options = -b
debug = off
track_info =
youtube_media_format = mp4
omx_location = /usr/bin/omxplayer
ytdl_location = /usr/bin/youtube-dl
ytdl_prefered_transcoder = ffmpeg
download_media_url_upon = play
geometry =
EOM

        # Create the executable
        cat <<EOM >$R/usr/local/bin/tboplayer
#!/bin/bash
python2 /usr/local/bin/tboplayer.py
EOM
        chmod +x $R/usr/local/bin/tboplayer

        # Create the .desktop entry.
        cat <<EOM >$R/usr/share/applications/tboplayer.desktop
[Desktop Entry]
Version=1.0
Name=GUI for OMXPlayer
GenericName=Media player
Comment=Play your multimedia streams
Exec=tboplayer
Icon=totem
Terminal=false
Type=Application
Categories=AudioVideo;Player;
MimeType=video/dv;video/mpeg;video/x-mpeg;video/msvideo;video/quicktime;video/x-anim;video/x-avi;video/x-ms-asf;video/x-ms-wmv;video/x-msvideo;video/x-nsv;video/x-flc;video/x-fli;video/x-flv;video/vnd.rn-realvideo;video/mp4;video/mp4v-es;video/mp2t;application/ogg;application/x-ogg;video/x-ogm+ogg;audio/x-vorbis+ogg;audio/ogg;video/ogg;application/x-matroska;audio/x-matroska;video/x-matroska;video/webm;audio/webm;audio/x-mp3;audio/x-mpeg;audio/mpeg;audio/x-wav;audio/x-mpegurl;audio/x-scpls;audio/x-m4a;audio/x-ms-asf;audio/x-ms-asx;audio/x-ms-wax;application/vnd.rn-realmedia;audio/x-real-audio;audio/x-pn-realaudio;application/x-flac;audio/x-flac;application/x-shockwave-flash;misc/ultravox;audio/vnd.rn-realaudio;audio/x-pn-aiff;audio/x-pn-au;audio/x-pn-wav;audio/x-pn-windows-acm;image/vnd.rn-realpix;audio/x-pn-realaudio-plugin;application/x-extension-mp4;audio/mp4;audio/amr;audio/amr-wb;x-content/audio-player;application/xspf+xml;x-scheme-handler/mms;x-scheme-handler/rtmp;x-scheme-handler/rtsp;
Keywords=Player;Audio;Video;
EOM

        # nodered
        wget -c "${NODERED}" -O $R/tmp/nodered.deb
        chroot $R gdebi -n /tmp/nodered.deb

        # Scratch (nuscratch)
        # - Requires: scratch wiringpi
        wget -c "${WIRINGPI}" -O $R/tmp/wiringpi.deb
        chroot $R gdebi -n /tmp/wiringpi.deb
        wget -c "${SCRATCH}" -O $R/tmp/scratch.deb
        chroot $R gdebi -n /tmp/scratch.deb
        chroot $R apt-get -y install nuscratch
        rm -f $R/usr/share/applications/squeak.desktop || true
        cat <<EOM >$R/etc/sudoers.d/scratch
# Allow members of group gpio to execute scratch and sqweak
%gpio ALL=NOPASSWD: /usr/bin/scratch
%gpio ALL=NOPASSWD: /usr/bin/squeak
EOM

        # Minecraft
        chroot $R apt-get -y install minecraft-pi

        # Sonic Pi
        chroot $R apt-get -y install sonic-pi

        # raspi-config - Needs forking/modifying to support Ubuntu
        #chroot $R apt-get -y install raspi-config rc-ui
    fi
}

function tweak_flavour() {
    if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        # Disable compositing, by default.
        cat <<EOM >$R/usr/share/glib-2.0/schemas/zubuntu-mate.gschema.override
[org.mate.Marco.general]
compositing-manager=false
EOM

        # Pre-cache MATE Menu
        rsync -a skel/ $R/etc/skel/
        chown -R root:root $R/etc/skel

        # Purge the massive LibreOffice SVG icons.
        cat <<'EOM' >$R/etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

rm -f /usr/share/icons/hicolor/scalable/apps/libreoffice-*.svg || true
rm -f /usr/share/applications/squeak.desktop || true

exit 0
EOM
        rm -f $R/usr/share/icons/hicolor/scalable/apps/libreoffice-*.svg || true
        chroot $R glib-compile-schemas /usr/share/glib-2.0/schemas/
        chroot $R update-icon-caches /usr/share/icons/hicolor/
        chroot $R update-desktop-database
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

    # Clean up old Raspberry Pi firmware and modules
    rm -f $R/boot/.firmware_revision || true
    rm -rf $R/boot.bak || true
    rm -rf $R/lib/modules/4.1.7* || true
    rm -rf $R/lib/modules.bak || true

    # Potentially sensitive.
    rm -f $R/root/.bash_history
    rm -f $R/root/.ssh/known_hosts

    # Machine-specific, so remove in case this system is going to be
    # cloned.  These will be regenerated on the first boot.
    rm -f $R/etc/udev/rules.d/70-persistent-cd.rules
    rm -f $R/etc/udev/rules.d/70-persistent-net.rules
    rm -f $R/etc/NetworkManager/system-connections/*
    [ -L $R/var/lib/dbus/machine-id ] || rm -f $R/var/lib/dbus/machine-id
    echo '' > $R/etc/machine-id

    # Enable cofi
    if [ -e $R/etc/ld.so.preload.disable ]; then
        mv -v $R/etc/ld.so.preload.disable $R/etc/ld.so.preload
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
    add_scripts
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
    tweak_flavour
    apt_upgrade
    apt_clean
    clean_up
    umount_system
    make_raspi2_image ${FS_TYPE} ${FS_SIZE}
}

stage_01_base
stage_02_desktop
stage_03_raspi2
