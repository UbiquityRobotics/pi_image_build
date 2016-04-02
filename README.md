# Ubuntu MATE 16.04 for the Raspberry Pi 2 and Raspberry Pi 3.

Martin Wimpress and Rohith Madhavan have made an Ubuntu MATE image
for the Raspberry Pi 2 and Raspberry PI 3 which you can download or
build yourself.

The image is functional and based on the regular Ubuntu `armhf` base,
not the new Snappy Core, which means that the installation procedure for
applications is the same as that for the regular desktop version, ie using
`apt-get`.

We have done what we can to optimise the build for the Raspberry Pi
and one can comfortably use applications such as LibreOffice, which in
fact is a joy to use :-) But the microSDHC I/O throughput is a
bottleneck so **we recommend that you use a Class 6 or Class 10 microSDHC**
card.

You'll need a microSD card which is 4GB or greater to fit the image.
The file system can be resized to occupy the unallocated space of the
microSD card, similar to Raspbian.

**NOTE! There are no predefined user accounts**. The first time you
boot the Ubuntu MATE image it will run through a setup wizard where you
can create your own user account and configure your regional settings.
The first boot is quite slow, but once the first boot configuration is
complete subsequent boots are much quicker.

## Download

A pre-built image available from the Ubuntu MATE website.

  * <https://ubuntu-mate.org/raspberry-pi/>

## Putting the image on microSDHC

Download the image and then:

  1. Extract the `.img.bz2` archive to get the image file.

    bunzip2 ubuntu-mate-16.04-desktop-armhf-raspberry-pi.img.bz2

  2. Write the image file to the microSD card as root.

    sudo ddrescue -d -D --force ubuntu-mate-16.04-desktop-armhf-raspberry-pi.img /dev/sdX

The drive may be mounted on any `/dev/sdX` so use the command `lsblk` to
check.

## Re-size file system

There are no utilities included for automatic file system re-sizing. However,
it's not hard to do manually. Once booted:

    `sudo fdisk /dev/mmcblk0`

Delete the second partition (d, 2), then re-create it using the defaults
(n, p, 2, enter, enter), then write and exit (w). Reboot the system, then:

    `sudo resize2fs /dev/mmcblk0p2`

## Enable and Disable X11

We created a simple utility called `graphical` to disable/enable the
MATE desktop environment for easily creating a headless *"server"*.
Executing `graphical disable` will present a console login on the next
boot, with now X11 or associated services running. If you want to get
the full Ubuntu MATE desktop back, run `graphical enable` and reboot.

## Hardware accelerated video

Most videos will play with hardware acceleration using `omxplayer` which
is pre-installed in Ubuntu MATE. However if you have MPEG-2 or VC-1 video
video files then **you will need MPEG-2 and/or VC-1 licenses from the
[Raspberry Pi Store](http://www.raspberrypi.com/license-keys/)**.

### Redirecting audio output

You can select which audio device `omxplayer` should output audio to.

#### For HDMI

    omxplayer -o hdmi video.mp4

#### For 3.5mm audio jack

    omxplayer -o local video.mp4

The sound will output to HDMI by default if both HDMI and the 3.5mm audio jack
are connected. You can, however, force the system to output to a particular
device using `amixer`.

#### For HDMI

    sudo amixer cset numid=3 2

#### For 3.5mm audio jack

    sudo amixer cset numid=3 1

## Feedback and Improvements

Please post all feedback on the [dedicated community topic](https://ubuntu-mate.community/t/ubuntu-mate-15-04-for-raspberry-pi-2/517).
If you have any improvements then please submit a pull request to our
BitBucket.

  * <https://bitbucket.org/ubuntu-mate/ubuntu-mate-rpi2>

## Credits

  * [Rohith Madhavan](http://rohithmadhavan.com) - Made the Ubuntu MATE 15.04 image.
  * [Martin Wimpress](https://flexion.org) - Added first boot setup wizard and architecture optimisations.
  * [Ryan Finnie](http://finnie.org) - Raspberry Pi 2 Kernel, Firmware and video driver packages.
  * [Sjoerd Simons](http://sjoerd.luon.net) - Made the initial Raspberry Pi 2 kernel patches for Debian Jessie.
  * [Sergio Conde](http://omxplayer.sconde.net/) - Maintains `omxplayer` for the Raspberry Pi.
  * [Spindle](https://github.com/RPi-Distro/spindle) - a tool to help spin distribution images

## Changes

### 2016-03-03 - 16.04 beta 1 for Raspbery Pi 2 and Raspberry Pi 3

  * Updated BlueZ 5.37 with patches to support the Raspberry Pi 3 integrated Bluetooth.
  * Updated to Linux 4.1.19.
  * Updated to `raspberrypi-firmware` 1.20160315-1.
  * Updated to `omx-player` 0.3.7~git20160206~cb91001.
  * Updated to `wiringpi` 2.32.
  * Updated to `nuscratch` 20160115.
  * Updated to `sonic-pi` 2.9.0-1.
  
  * Migrated configuration tweaks to `raspberrypi-general-mods` and `raspberrypi-sys-mods`.
  
### 2016-02-27 - 15.10.3 for Raspbery Pi 2 and Raspberry Pi 3

  * Added support for Raspberry Pi 3 integrated Wifi.
  * Updated BlueZ 5.35 with patches to support the Raspberry Pi 3 integrated Bluetooth.
  * Support for the integrated Raspberry Pi 3 Bluetooth is not working but we hope to have an update that addresses this soon.

### 2016-02-26 - 15.10.2 for Raspbery Pi 2 and Raspberry Pi 3 (internal testing build)

  * Added support for Raspberry Pi 3 Model B.
  * No Raspberry Pi 3 integrated Wifi or Bluetooth support.
  * Updated to Linux 4.1.18.
  * Updated all packages to the current version in the Ubuntu 15.10 archive.
  * Fixed an issue where the SSH host keys were not correctly regenerated on first boot.

### 2015-10-22 - Ubuntu MATE 15.10 for Raspbery Pi 2 Final Release

  * Added OMXPlayer GUI.
  * Added YouTube Downloader.
  * Added `fake-hwclock`.
  * Added `python-spidev` and `python3-spidev`.
  * Added `python-codebug-tether` and `python3-codebug-tether`.
  * Added `python-codebug-i2c-tether` and `python3-codebug-i2c-tether`.
  * Added file system integrity checking on first boot.
  * Optimised first run of MATE Menu.
  * Optimised LibreOffice icons.
  * Reinstated `oem-config`, which has been patched for the Raspberry Pi 2.
    * Now includes the Ubuntu MATE slideshow.
  * Fixed udev rules and groups for accessing `spi`.
  * Fixed Scratch, it now runs via a `sudo` wrapper.
    * Simliar to how Raspbian does it except *only* Scratch can be executed with elevated privileges, not everything.
  * Removed Compiz.

### 2015-10-14 - Ubuntu MATE 15.10 for Raspbery Pi 2 Release Candidate

  * Fixed framebuffer so it now uses 32-bit colour depth.
  * Added Minecraft Pi Edition 0.1.1-4.
  * Added Scratch 20150916.
  * Added Sonic Pi 2.7.0-1.
  * Added essential Python 2.7.x and Python 3.4.x libraries.
  * Added `raspi-gpio`.
  * Added `python-rpi.gpio` and `python3-rpi.gpio`.
  * Added `python-serial` and `python3-serial`.
  * Added `python-picamera` and `python3-picamera`.
  * Added `python-sense-hat` and `python3-sense-hat`.
  * Added `python-astropi` and `python3-astropi`.
  * Added `python-pygame` and `python3-pygame`.
  * Added `udev` rules for `gpio`, `input`, `i2c`, `spi`, `vchiq`.
  * Added `/usr/local/sbin/adduser.local` hook to automatically add new users to the `adm`, `gpio`, `i2c`, `input`, `spi` and `video` groups.
  * Added `openssh-server` with first-boot host key regeneration.
  * Added `graphical` a utility to disable/enable the MATE desktop environment for easily creating a headless *"server"*.
  * Updated to Linux 4.1.10.
    * Now using the kernel, firmware and drivers from Raspberry Pi Foundation and includes `rpi-update` to easily update the kernel and firmware.
  * Updated `/boot/config.txt` so it is now fully documented.
  * Updated to `raspi-copies-and-fills` (high performance memcpy and memset) 0.5-1.
  * Updated to `xserver-xorg-video-fbturbo` (an accelerated x.org driver) 0~git.20151007.f9a6ed7.
  * Updated to `omx-player` 0.3.6~git20150912~d99bd86.
  * Updated `/boot/config.txt` so when HDMI is connected audio is sent over HDMI by default.
  * Enabled Plymouth to improve startup and shutdown performance.
  * Removed `oem-config`.

### 2015-04-22 - Ubuntu MATE 15.04 for Raspberry Pi 2 Final Release

  * Enabled Ryan Finnie's PPA.
    * <https://launchpad.net/~fo0bar/+archive/ubuntu/rpi2>
    * Many thanks to Ryan for adding Vivid as a build target.
  * Changed from `cfq` to `deadline` I/O scheduler.
  * Added `xserver-xorg-video-fbturbo` (an accelerated x.org driver) 0~git.20150305.e094e3c-1.15.04.
    * Limited to hardware accelerated window moving and scrolling.
  * Added `raspi-copies-and-fills` (high performance memcpy and memset) 0.4-1.
  * Added `oem-config` so first boot provides a setup wizard.
  * Added `rpi2-ubuntu-errata` for facilitating post-release updates/migrations.
  * Added sym-links to VideoCore utilties in `/opt/vc/` for 3rd party script compatibility.
  * Added `f2fs` support to the build script.
    * Pre-built images available for download use `ext4` because `f2fs` file systems can not be resized
    at present.
  * Updated to Linux 3.18.0-20.21.
  * Updated to `flash-kernel` 3.0~rc.4ubuntu54+rpi2.4.
  * Updated to `omxplayer` 0.3.6~git20150402~74aac37.
  * Updated to `raspberrypi-firmware-nokernel` 1.20150402.3ea439c-1.
  * Updated to `raspberrypi-vc` (VideoCore GPU libraries) 1.20150323.7650bcb-1.
  * Fixed `/etc/network/interfaces` so that the Ethernet device is now configurable via Network Manager.
  * Removed `openssh-server` until host key regeneration can be integrated.

### 2015-03-14 - Ubuntu MATE 15.04 for Raspberry Pi 2 Beta 2

  * Enabled `systemd` as the init system.
  * Added `raspberrypi-vc` (VideoCore GPU libraries) 1.20150301.0de0b20-3.
  * Added `omxplayer` 0.3.6~git20150217~5337be8.
  * Added `linux-firmware`.
  * Added `openssh-server`.

### 2015-03-07 - Ubuntu MATE 15.04 for Raspberry Pi 2 Beta 1

  * Initial Release.

## TODO

  * Add automatic reszing of the root file system.
  * Add `raspi-config` or equivilent.
