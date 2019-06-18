#!/usr/bin/env bash

########################################################################
#
# Copyright (C) 2015 Martin Wimpress <code@ubuntu-mate.org>
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

FLAVOUR="hbrc-fpga"
RELEASE="xenial"
VERSION="16.04.2"
QUALITY=""

# Either 'ext4' or 'f2fs'
FS_TYPE="ext4"

# Target image size, will be represented in GB
FS_SIZE=8

# Either 0 or 1.
# - 0 don't make generic rootfs tarball
# - 1 make a generic rootfs tarball
MAKE_TARBALL=0

TARBALL="${FLAVOUR}-${VERSION}${QUALITY}-desktop-armhf-rootfs.tar.bz2"
TIMESTAMP=$(date +%Y-%m-%d)	
IMAGE="${TIMESTAMP}-hbrc-fpga-rpi.img"
IMAGEDIR=/image-builds/final-images/
mkdir -p /image-builds/final-images/
BASEDIR=/image-builds/PiFlavourMaker/${RELEASE}
BUILDDIR=${BASEDIR}/${FLAVOUR}
BASE_R=${BASEDIR}/base
DESKTOP_R=${BUILDDIR}/desktop
DEVICE_R=${BUILDDIR}/pi
ARCH=$(uname -m)
export TZ=UTC
locale-gen "en_US.UTF-8"
update-locale

IMAGE_HOSTNAME="homebrew"

USERNAME="ubuntu"
OEM_CONFIG=0

GUI=1
MAGNI_AUTOSTART=0

LOCAL_MIRROR=http://us-east-2.ec2.ports.ubuntu.com/ubuntu-ports
