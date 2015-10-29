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

FLAVOUR="ubuntu-mate"
RELEASE="wily"
POINT=".1"
QUALITY=""
# Either 'ext4' or 'f2fs' - f2fs has not been tested in while
FS_TYPE="ext4"

# Either 4, 8 or 16
FS_SIZE=4

# Either 0 or 1.
# - 0 don't make generic rootfs tarball
# - 1 make a generic rootfs tarball
MAKE_TARBALL=0

########################################################################
#
#      NO NEED TO EDIT BELOW HERE UNLESS YOU KNOW WHY YOU MUST         #
#
########################################################################

# Validate the release
if [ "${RELEASE}" != "vivid" ] && [ "${RELEASE}" != "wily" ] && [ "${RELEASE}" != "xenial" ]; then
    echo "ERROR! ${RELEASE} is not currently supported."
    exit 1
else
    if [ "${RELEASE}" == "vivid" ]; then
        VERSION="15.04${POINT}"
    elif [ "${RELEASE}" == "wily" ]; then
        VERSION="15.10${POINT}"
    elif [ "${RELEASE}" == "xenial" ]; then
        VERSION="16.04${POINT}"
    else
        echo "ERROR! ${RELEASE} is not currently supported."
        exit 1
    fi
fi

# Validate the flavour
if [ "${FLAVOUR}" == "ubuntu-minimal" ] || [ "${FLAVOUR}" == "ubuntu-standard" ]; then
    FLAVOUR_NAME="Ubuntu"
    USERNAME="ubuntu"
    OEM_CONFIG=0
else
    if [ "${FLAVOUR}" == "lubuntu" ]; then
        FLAVOUR_NAME="Lubuntu"
    elif [ "${FLAVOUR}" == "kubuntu" ]; then
        FLAVOUR_NAME="Kubuntu"
    elif [ "${FLAVOUR}" == "ubuntu" ]; then
        FLAVOUR_NAME="Ubuntu"
    elif [ "${FLAVOUR}" == "ubuntu-gnome" ]; then
        FLAVOUR_NAME="Ubuntu GNOME"
    elif [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        FLAVOUR_NAME="Ubuntu MATE"
    elif [ "${FLAVOUR}" == "xubuntu" ]; then
        FLAVOUR_NAME="Xubuntu"
    else
        echo "ERROR! ${FLAVOUR} is not currently supported."
        exit 1
    fi
    USERNAME="${FLAVOUR}"
    OEM_CONFIG=1
fi

TARBALL="${FLAVOUR}-${VERSION}${QUALITY}-desktop-armhf-rootfs.tar.bz2"
IMAGE="${FLAVOUR}-${VERSION}${QUALITY}-desktop-armhf-raspberry-pi-2.img"
BASEDIR=${HOME}/build/${RELEASE}
BUILDDIR=${BASEDIR}/${FLAVOUR}
BASE_R=${BASEDIR}/base
DESKTOP_R=${BUILDDIR}/desktop
DEVICE_R=${BUILDDIR}/pi2
ARCH=$(uname -m)
export TZ=UTC

# Override OEM_CONFIG here if required. Either 0 or 1.
# - 0 to hardcode a user.
# - 1 to use oem-config.
#OEM_CONFIG=1

if [ ${OEM_CONFIG} -eq 1 ]; then
    USERNAME="oem"
fi
