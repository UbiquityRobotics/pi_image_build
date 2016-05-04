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

function make_hash() {
    source ${HOME}/Roaming/Scripts/key
    local FILE="${1}"
    local HASH="${2}"
    if [ ! -f ${FILE}.${HASH}.sign ]; then
        if [ -f ${FILE} ]; then
            ${HASH}sum ${FILE} > ${FILE}.${HASH}
            sed -i -r "s/ .*\/(.+)/  \1/g" ${FILE}.${HASH}
            gpg --default-key ${KEY} --armor --output ${FILE}.${HASH}.sign --detach-sig ${FILE}.${HASH}
        else
            echo "WARNING! Didn't find ${FILE} to hash."
        fi
    else
        echo "Existing signature found, skipping..."
    fi
}

function publish_image() {
    source ${HOME}/Roaming/Scripts/dest
    local HASH=sha256
    if [ -n "${DEST}" ]; then
        echo "Sending to: ${DEST}"
        if [ ! -e "${BASEDIR}/${IMAGE}.xz" ]; then
            xz ${BASEDIR}/${IMAGE}
        fi
        make_hash "${BASEDIR}/${IMAGE}.xz" ${HASH}
        ssh ${DEST} mkdir -p ~/ISO-Mirror/${RELEASE}/armhf/
        rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${IMAGE}.xz" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
        rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${IMAGE}.xz.${HASH}" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
        rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${IMAGE}.xz.${HASH}.sign" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
    fi
}

function publish_tarball() {
    if [ ${MAKE_TARBALL} -eq 1 ]; then
        source ${HOME}/Roaming/Scripts/dest
        local HASH=sha256
        if [ -n "${DEST}" ]; then
            if [ ! -e "${BASEDIR}/${TARBALL}" ]; then
                echo "ERROR! Could not find ${TARBALL}. Exitting."
                exit 1
            fi
            make_hash "${BASEDIR}/${TARBALL}" ${HASH}
            echo "Sending to: ${DEST}"
            rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${TARBALL}" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
            rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${TARBALL}.${HASH}" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
            rsync -rvl -e 'ssh -c aes128-gcm@openssh.com' --progress "${BASEDIR}/${TARBALL}.${HASH}.sign" ${DEST}:ISO-Mirror/${RELEASE}/armhf/
        fi
    fi
}

publish_image
publish_tarball
