# Raspberry Pi package porting

These rough notes keep track of what Raspberry Pi packages have been
"ported" to the Ubuntu Pi Flavour Makers PPA.

## Hardware stuff

These are ported.

  * http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/
  * https://launchpad.net/~fo0bar/+archive/ubuntu/rpi2-nightly/+files/

These are pending.

Sadly COFI fails to build in a PPA :-(

  * http://archive.raspberrypi.org/debian/pool/main/r/raspi-copies-and-fills/

These are for reference.

  * https://twolife.be/raspbian/pool/main/bcm-videocore-pkgconfig/
  * https://twolife.be/raspbian/pool/main/linux/

## Applications

These are ported.

  * https://archive.raspberrypi.org/debian/pool/main/m/minecraft-pi/
  * http://archive.raspberrypi.org/debian/pool/main/r/raspi-gpio/
  * http://archive.raspberrypi.org/debian/pool/main/s/sonic-pi/
  * http://archive.raspberrypi.org/debian/pool/main/p/picamera/
  * http://archive.raspberrypi.org/debian/pool/main/n/nuscratch/ (Modify wrapper in debian/scratch to just be "sudo ")
  * http://archive.raspberrypi.org/debian/pool/main/r/rtimulib/
  * http://archive.raspberrypi.org/debian/pool/main/r/raspi-config/
  * http://archive.raspberrypi.org/debian/pool/main/r/rc-gui/
  * http://archive.raspberrypi.org/debian/pool/main/r/rpi.gpio/ (Hardcode target Python 3.x version in debian/rules)
  * http://archive.raspberrypi.org/debian/pool/main/s/spidev/
  * http://archive.raspberrypi.org/debian/pool/main/c/codebug-tether/ (Hardcode target Python 3.x in debian/rules)
  * http://archive.raspberrypi.org/debian/pool/main/c/codebug-i2c-tether/ (Hardcode target Python 3.x in debian/rules)
  * http://archive.raspberrypi.org/debian/pool/main/c/compoundpi/
  * http://archive.raspberrypi.org/debian/pool/main/p/python-sense-hat/
  * http://archive.raspberrypi.org/debian/pool/main/a/astropi/
  * http://archive.raspberrypi.org/debian/pool/main/s/sense-hat/

These are pending.

  * http://archive.raspberrypi.org/debian/pool/main/p/pgzero/
  * https://archive.raspberrypi.org/debian/pool/main/e/epiphany-browser/

These FTBFS.

  * http://archive.raspberrypi.org/debian/pool/main/g/gst-omx1.0/
  * https://twolife.be/raspbian/pool/main/omxplayer/  

## Kodi

Kodi builds are currently a work in progress, these are the references:

  * http://archive.mene.za.net/raspbian/pool/unstable/k/kodi/
  * https://twolife.be/raspbian/pool/main/kodi/

The build is based on https://twolife.be/raspbian/pool/main/kodi/
with some additions taken from http://archive.mene.za.net/raspbian/pool/unstable/k/kodi/.

Unrecognized options:

  * --disable-maintainer-mode
  * --disable-sdl
  * --disable-projectm  Music visualisations
  * --disable-rsxs      Disables screensavers
  * --disable-goom      Audio visualisation

Some options that might be worth testing:

  * --disable-xrandr
  * --disable-joystick
  * --enable-airplay    B-D libshairplay AirTunes
  * --enable-mid        Option to enable MID Moblin support at compile time. Sets vsync disabled as default and sets the goom texture and thumb size to 256.
  * --enable-rsxs       Appears to enable screensavers. 
  * --enable-afpclient
  * --enable-non-free
  * --enable-dvdcss     Enable encrpyted DVD playback
  * --enable-ccache     B-D ccache
  * --enable-alsa       ALSA support is built with the current configuration
  * --enable-libusb     B-D libusb
  * --enable-libbluray
  * --enable-optical-drive
  * --enable-dvdcss

Probably need to ship ~/.ffmpeg that sets mmal as the default.
