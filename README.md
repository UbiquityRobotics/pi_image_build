# Ubiquity Robotics Raspberry Pi Images

## Download

A pre-built image available from our website.

  * <https://downloads.ubiquityrobotics.com/>

## Login details

The default user account is `ubuntu` with password `ubuntu`.

## Putting the image on microSDHC

Download the image and then:

We recommend using the GNOME Disks tool to flash images onto the Micro SD card as it has native support for xz compressed images. 

If you haven't installed it, simply run `sudo apt install gnome-disk-utility`. 

Then you can double click on the downloaded image file, the GNOME Disks tool will automatically come up, and you can direct it to flash the image on to an SD card drive attached to your computer.

## Re-size file system

The filesystem is automatically resized to fill the SD card on first boot.

## Pifi
By default the image uses pifi for AP mode configuration.

The AP name is UbiquityRobot followed by the last 4 digits of the pi MAC address.

The AP password is `robotseverywhere`

More details here: https://github.com/rohbotics/pifi

## Enable and Disable X11
By default the image comes up with X11 and and lxde desktop environment.

Enable by running `graphical enable` in a terminal on the pi.

Disable with `graphical disable`.

## Magni Autostart
By default the image boots up running the core code needed on a Magni platform.

Stop on this boot with `sudo systemctl stop magni-base`.

Disable with `sudo systemctl disable magni-base`.

Re-enable with `sudo systemctl enable magni-base`.

## RTC
The image is setup to use an `mcp7940x` RTC by default.

You may want to use a different RTC by changing the line `dtoverlay=i2c-rtc,mcp7940x` in your `/boot/config.txt`.

The systemd service `hwclock-sync` is responsible for syncing the system clock with the RTC on first boot, if you don't have an RTC you may wish to disable it.

`systemctl disable hwclock-sync.service`
