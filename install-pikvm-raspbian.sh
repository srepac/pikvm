#!/bin/bash
# created by @srepac   08/09/2011   srepac@kvmnerds.com
# Scripted Installer of Pi-KVM on Raspbian 32-bit and 64-bit RPi 3A+, 4B, 400, Zero (2) W, and CM4 (CSI0)
#
# *** MSD is disabled by default ***
#
# Mass Storage Device requires the use of a USB thumbdrive or SSD and will need to be added in /etc/fstab
: '
# SAMPLE /etc/fstab entry for USB drive with only one partition formatted as ext4 for the entire drive:

/dev/sda1  /var/lib/kvmd/msd   ext4  nodev,nosuid,noexec,ro,errors=remount-ro,data=journal,X-kvmd.otgmsd-root=/var/lib/kvmd/msd,X-kvmd.otgmsd-user=kvmd  0  0

'
# NOTE:  This was tested on a new install of raspbian desktop and lite versions, but should also work on an existing install.
#
# Last change 20220328 0720 PDT
VER=4.1
#
# Changelog:
# 1.0   from August 2021
# 2.0   Feb 2022 - updated to work with bullseye
# 3.0   Feb 2022 - updated to include support for Zero 2W (tested to work with Z2W, Pi4 and CM4)
#       ... testing performed by @SEAT and @Mark Jim     Thank you guys!!!
# 3.1   Feb 2022 - compile ttyd for bullseye, but use deb packages for buster 32-bit
# 3.2   Feb 2022 - changed to compile libwesockets and ttyd for all OS's
# 3.3   Feb 2022 - reverted 3.2 change
# 3.3.1 Feb 2022 - cleanup /tmp/ustreamer and /tmp/ttyd before downloading from git and building
# 3.3.2 Feb 2022 - added support for zero w install
# 3.3.3 02/18/22 - added pi 3A+ support; also switched from if-elif-else to using case statements
# 3.3.4 02/19/22 - updated gpu_mem to be 64, 96, 128, and 256 based on pi board
# 3.3.5 02/20/22 - Added logging file for the install (example /var/kvmd/cache/installer-20220220-07:30:30.log)
# 3.3.6 02/22/22 - force pi400 to use hdmiusb image and pi400 specific changes in udev rules and hdmiusb-check script
# 3.3.7 02/22/22 - refactoring
# 3.3.8 02/23/22 - added python3-serial dependency for xh_hk4401 kvm support
# 3.3.9 02/23/22 - download pistat, pi-temp, and pikvm-info scripts to /usr/local/bin/
# 3.4   02/24/22 - updated 3A to use rpi4 platform package as the rpi3 package doesn't support webrtc
# 3.4.1 02/24/22 - if /usr/bin/janus already exists from previous install, do not extract janus package from REPO
# 3.4.2 02/24/22 - additional check that /usr/bin/janus runs properly, otherwise replace it with janus REPO package
# 3.4.3 02/25/22 - add kvmd user to dialout group -- required for xh_hk4401 support per @bobiverse
# 3.4.4 02/25/22 - check to make sure python 3.7 or 3.9 are installed; gracefully exit otherwise 
# 3.4.5 02/25/22 - save /etc/motd to /etc/motd.orig and fix zero2W case statement
# 3.4.6 02/25/22 - re-run part 1 if /usr/bin/kvmd doesn't exist or -f (force) option is selected
# 3.5   02/25/22 - added restore-configs function to restore configurations from previous install
# 3.5.1 02/26/22 - redirect stderr when restoring configs (clean install) -- handle non-existent .save files
# 3.5.2 02/27/22 - update motd and python3 -V check 
# 3.5.3 02/28/22 - change pointer from blue blob to crosshair 
# 3.5.4 03/01/22 - add support for v0 (pi1/2/3 platforms); confirmation to proceed after platform is selected
# 3.5.5 03/01/22 - build wiringpi from source
# 3.5.6 03/06/22 - make sure script is run as root
# 3.5.7 03/13/22 - use my ustreamer fork of 4.13 version (just in case 5.0) 
# 4.0   03/27/22 - build ustreamer 5.x (kernel 5.15) or 4.x (kernel 5.10) depending on kernel version
# 4.1   03/27/22 - updated cmd_remove section to only apply when kernel 5.10 AND ( aarch64 OR any bullseye variant ) 

set +x
# Added on 03/06/22 -- check to make sure user is running the script as root.
WHOAMI=$( whoami )
if [[ $WHOAMI != "root" ]]; then
  echo "$WHOAMI, this must be run as root."
  exit 1
fi

export PIKVMREPO="https://kvmnerds.com/REPO"
export KVMDCACHE="/var/cache/kvmd"; mkdir -p ${KVMDCACHE}
export PKGINFO="${KVMDCACHE}/packages.txt"
export LOGFILE="${KVMDCACHE}/installer-$(date +%Y%m%d-%H:%M:%S).log"; touch $LOGFILE

### 02/25/2022 -- script does not work on raspbian with python 3.10 and higher or 3.6 and lower
PYTHONVER=$( python3 -V | awk '{print $2}' | cut -d'.' -f1,2 )
case $PYTHONVER in 
  "3.7"|"3.9")   # only supported versions of python
    ;;
  *) 
    printf "\nYou are running python ${PYTHONVER}.  Installer (for kvmd 3.47) only works with python 3.7 -OR- 3.9.\n"
    exit 1
    ;;
esac

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage:  $0 [-f]   where -f will force re-install new pikvm platform"
  exit 1
fi

WHOAMI=$( whoami )
if [ "$WHOAMI" != "root" ]; then
  echo "$WHOAMI, please run script as root."
  exit 1
fi

press-enter() {
  echo
  read -p "Press ENTER to continue or CTRL+C to break out of script."
} # end press-enter

gen-ssl-certs() {
  cd /etc/kvmd/nginx/ssl
  openssl ecparam -out server.key -name prime256v1 -genkey
  openssl req -new -x509 -sha256 -nodes -key server.key -out server.crt -days 3650 \
        -subj "/C=US/ST=Denial/L=Denial/O=Pi-KVM/OU=Pi-KVM/CN=$(hostname)"
  cp server* /etc/kvmd/vnc/ssl/
} # end gen-ssl-certs

create-override() {
  if [ $( grep ^kvmd: /etc/kvmd/override.yaml | wc -l ) -eq 0 ]; then

    if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then
      cat <<USBOVERRIDE >> /etc/kvmd/override.yaml
kvmd:
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt  # allow absolute/relative mouse mode
    msd:
        type: disabled
    streamer:
        forever: true
        cmd_append:
            - "--slowdown"      # for usb dongle (so target doesn't have to reboot)
        resolution:
            default: 1280x720
USBOVERRIDE

    else

      cat <<CSIOVERRIDE >> /etc/kvmd/override.yaml
kvmd:
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt
    msd:
        type: disabled
    streamer:
        forever: true
        cmd_append:
            - "--slowdown"      # so target doesn't have to reboot
CSIOVERRIDE

      if [[ $KERNELVER == "5.10" && ( $( uname -m ) == "aarch64" || $( grep -i codename /etc/os-release | cut -d'"' -f2 ) == "bullseye" ) ]]; then
        ### this only applies if 5.10 kernel AND ( aarch64 OR any bullseye variant) ###
        cat <<BULLSEYEOVERRIDE >> /etc/kvmd/override.yaml
        ### these are required in case we're running bullseye or 64bit OS
        ### hardware OMX is not supported and h264 options are only available with OMX ###
        cmd_remove:
            - "--encoder=omx"
            - "--h264-sink=kvmd::ustreamer::h264"
            - "--h264-sink-mode=0660"
            - "--h264-bitrate={h264_bitrate}"
            - "--h264-gop={h264_gop}"
BULLSEYEOVERRIDE
      fi

    fi

    ### added 03/01/22
    if [ $SERIAL -eq 1 ]; then     # use Arduino serial HID
      sed -i -e 's+    hid:$+    hid:\n        type: serial\n        reset_pin: 4\n        device: /dev/kvmd-hid\n+g' /etc/kvmd/override.yaml 
      sed -i -e 's+        mouse_alt:$+#        mouse_alt:+g' /etc/kvmd/override.yaml
      sed -i -e 's+            device:+#            device:+g' /etc/kvmd/override.yaml
    fi

  fi
} # end create-override

install-python-packages() {
  for i in aiofiles aiohttp appdirs asn1crypto async-timeout bottle cffi chardet click colorama cryptography dateutil dbus hidapi idna libgpiod marshmallow more-itertools multidict netifaces packaging passlib pillow ply psutil pycparser pyelftools pyghmi pygments pyparsing requests semantic-version serial setproctitle setuptools six spidev systemd tabulate urllib3 wrapt xlib yaml yarl
  do
    echo "apt-get install python3-$i -y"
    apt-get install python3-$i -y > /dev/null
  done
} # end install python-packages

otg-devices() {
  modprobe libcomposite
  if [ ! -e /sys/kernel/config/usb_gadget/kvmd ]; then
    mkdir -p /sys/kernel/config/usb_gadget/kvmd/functions
    cd /sys/kernel/config/usb_gadget/kvmd/functions
    mkdir hid.usb0  hid.usb1  hid.usb2  mass_storage.usb0
  fi
} # end otg-device creation

install-tc358743() {
  ### https://www.linux-projects.org/uv4l/installation/ ###
  ### CSI Support for Raspbian ###
  curl https://www.linux-projects.org/listing/uv4l_repo/lpkey.asc | apt-key add -
  echo "deb https://www.linux-projects.org/listing/uv4l_repo/raspbian/stretch stretch main" | tee /etc/apt/sources.list.d/uv4l.list

  apt-get update > /dev/null
  echo "apt-get install uv4l-tc358743-extras -y"
  apt-get install uv4l-tc358743-extras -y > /dev/null
} # install package for tc358743

boot-files() {
  if [[ $( grep srepac /boot/config.txt | wc -l ) -eq 0 ]]; then

    if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then  # hdmiusb platforms

      if [ $SERIAL -ne 1 ]; then  # v2 hdmiusb
        cat <<FIRMWARE >> /boot/config.txt
# srepac custom configs
###
hdmi_force_hotplug=1
gpu_mem=${GPUMEM}
enable_uart=1
#dtoverlay=tc358743
dtoverlay=disable-bt
dtoverlay=dwc2,dr_mode=peripheral
dtparam=act_led_gpio=13

# HDMI audio capture
#dtoverlay=tc358743-audio

# SPI (AUM)
#dtoverlay=spi0-1cs

# I2C (display)
dtparam=i2c_arm=on

# Clock
dtoverlay=i2c-rtc,pcf8563
FIRMWARE

      else   # v0 hdmiusb

        cat <<SERIALUSB >> /boot/config.txt
hdmi_force_hotplug=1
gpu_mem=16
enable_uart=1
dtoverlay=disable-bt

# I2C (display)
dtparam=i2c_arm=on

#
disable_overscan=1
SERIALUSB

      fi

    else   # CSI platforms

      if [ $SERIAL -ne 1 ]; then   # v2 CSI

        cat <<CSIFIRMWARE >> /boot/config.txt
# srepac custom configs
###
hdmi_force_hotplug=1
gpu_mem=${GPUMEM}
enable_uart=1
dtoverlay=tc358743
dtoverlay=disable-bt
dtoverlay=dwc2,dr_mode=peripheral
dtparam=act_led_gpio=13

# HDMI audio capture
dtoverlay=tc358743-audio

# SPI (AUM)
dtoverlay=spi0-1cs

# I2C (display)
dtparam=i2c_arm=on

# Clock
dtoverlay=i2c-rtc,pcf8563
CSIFIRMWARE

      else   # v0 CSI

        cat <<CSISERIAL >> /boot/config.txt
hdmi_force_hotplug=1
gpu_mem=16
enable_uart=1
dtoverlay=tc358743
dtoverlay=disable-bt

# I2C (display)
dtparam=i2c_arm=on

#
disable_overscan=1
CSISERIAL

      fi

      # add the tc358743 module to be loaded at boot for CSI
      if [[ $( grep -w tc358743 /etc/modules | wc -l ) -eq 0 ]]; then
        echo "tc358743" >> /etc/modules
      fi

      install-tc358743

    fi
  fi  # end of check if entries are already in /boot/config.txt

  # /etc/modules required entries for DWC2, HID and I2C
  # dwc2 and libcomposite only apply to v2 builds
  if [[ $( grep -w dwc2 /etc/modules | wc -l ) -eq 0 && $SERIAL -ne 1 ]]; then
    echo "dwc2" >> /etc/modules
  fi
  if [[ $( grep -w libcomposite /etc/modules | wc -l ) -eq 0 && $SERIAL -ne 1 ]]; then
    echo "libcomposite" >> /etc/modules
  fi
  if [[ $( grep -w i2c-dev /etc/modules | wc -l ) -eq 0 ]]; then
    echo "i2c-dev" >> /etc/modules
  fi

  printf "\n/boot/config.txt\n\n"
  cat /boot/config.txt
  printf "\n/etc/modules\n\n"
  cat /etc/modules
} # end of necessary boot files

get-packages() {
  printf "\n\n-> Getting Pi-KVM packages from ${PIKVMREPO}\n\n"
  echo "wget ${PIKVMREPO} -O ${PKGINFO}"
  wget ${PIKVMREPO} -O ${PKGINFO} 2> /dev/null
  echo

  # Download each of the pertinent packages for rpi3/4/zero2w/zerow, webterm, and the main service
  for pkg in `egrep 'janus|kvmd' ${PKGINFO} | grep -v sig | cut -d'>' -f3 | cut -d'"' -f2 | egrep -v 'fan|oled' | egrep 'rpi|zero|janus|webterm|kvmd-[0-9]'`
  do
    rm -f ${KVMDCACHE}/$pkg*
    echo "wget ${PIKVMREPO}/$pkg -O ${KVMDCACHE}/$pkg"
    wget ${PIKVMREPO}/$pkg -O ${KVMDCACHE}/$pkg 2> /dev/null
  done

  echo
  echo "ls -l ${KVMDCACHE}"
  ls -l ${KVMDCACHE}
  echo
} # end get-packages function

get-platform() {
  # get pi model
  model=$( tr -d '\0' < /proc/device-tree/model | cut -d' ' -f3,4,5 | sed -e 's/ //g' -e 's/Z/z/g' -e 's/Model//' -e 's/Rev//g'  -e 's/1.[0-9]//g' )

  case $model in

    "zero2W"|"zero2")
      # force platform to only use v2-hdmi for zero2w
      platform="kvmd-platform-v2-hdmi-zero2w"
      export GPUMEM=96
      ;;

    "zeroW")
      ### added on 02/18/2022
      # force platform to only use v2-hdmi for zerow
      platform="kvmd-platform-v2-hdmi-zerow"
      export GPUMEM=64
      ;;

    "3A"|"3APlus")
      ### added on 02/18/2022
      # force platform to only use v2-hdmi for rpi3 A+ ONLY
      # this script doesn't make distinction between rpi3 A, A+ or B
      ### it assumes you are using an rpi3 A+ that has the OTG support
      ### if your pikvm doesn't work (e.g. kb/mouse won't work), then
      ### ... rpi3 does NOT have an OTG port and will require arduino HID
      #platform="kvmd-platform-v2-hdmi-rpi3"    # this platform package doesn't support webrtc
      platform="kvmd-platform-v2-hdmi-rpi4"     # use rpi4 platform which supports webrtc
      export GPUMEM=96
      ;;

    "3B"|"2B"|"2A"|"B"|"A")
      ### added on 02/25/2022 but updated on 03/01/2022 (GPUMEM hardcoded to 16MB)
      echo "Pi ${model} board does not have OTG support.  You will need to use serial HID via Arduino." 
      SERIAL=1   # set flag to indicate Serial HID (default is 0 for all other boards)
      number=$( echo $model | sed 's/[A-Z]//g' )

      tryagain=1
      while [ $tryagain -eq 1 ]; do
        printf "Choose which capture device you will use:\n\n  1 - USB dongle\n  2 - v2 CSI\n"
        read -p "Please type [1-2]: " capture
        case $capture in
          1) platform="kvmd-platform-v0-hdmiusb-rpi${number}"; tryagain=0;;
          2) platform="kvmd-platform-v0-hdmi-rpi${number}"; tryagain=0;;
          *) printf "\nTry again.\n"; tryagain=1;;
        esac
      done
      ;;

    "400")
      ### added on 02/22/2022 -- force pi400 to use usb dongle as there's no CSI connector on it
      platform="kvmd-platform-v2-hdmiusb-rpi4"
      export GPUMEM=256
      ;;

    *)   ### default to use rpi4 platform image (this may also work with other SBCs with OTG)
      tryagain=1
      while [ $tryagain -eq 1 ]; do
        printf "Choose which capture device you will use:\n\n  1 - USB dongle\n  2 - v2 CSI\n  3 - V3 HAT\n"
        read -p "Please type [1-3]: " capture
        case $capture in
          1) platform="kvmd-platform-v2-hdmiusb-rpi4"; export GPUMEM=256; tryagain=0;;
          2) platform="kvmd-platform-v2-hdmi-rpi4"; export GPUMEM=128; tryagain=0;;
          3) platform="kvmd-platform-v3-hdmi-rpi4"; export GPUMEM=128; tryagain=0;;
          *) printf "\nTry again.\n"; tryagain=1;;
        esac
      done
      ;;

  esac

  echo | tee -a $LOGFILE
  echo "Platform selected -> $platform" | tee -a $LOGFILE
  echo | tee -a $LOGFILE

  printf "Please verify the platform selected above.\n"
  press-enter
} # end get-platform

install-kvmd-pkgs() {
  cd /

  INSTLOG="${KVMDCACHE}/installed_ver.txt"; rm -f $INSTLOG
  date > $INSTLOG

  # uncompress platform package first
  i=$( ls ${KVMDCACHE}/${platform}-*.tar.xz )
  echo "-> Extracting package $i into /" >> $INSTLOG
  tar xfJ $i

  # uncompress kvmd-{version} and kvmd-webterm packages
  for i in $( ls ${KVMDCACHE}/*.tar.xz | egrep 'kvmd-[0-9]|webterm' )
  do
    echo "-> Extracting package $i into /" >> $INSTLOG
    tar xfJ $i
  done

  # uncompress janus package if /usr/bin/janus doesn't exist
  if [ ! -e /usr/bin/janus ]; then
    i=$( ls ${KVMDCACHE}/*.tar.xz | egrep janus )
    echo "-> Extracting package $i into /" >> $INSTLOG
    tar xfJ $i

  else      # confirm that /usr/bin/janus actually runs properly
    /usr/bin/janus --version > /dev/null 2> /dev/null
    if [ $? -eq 0 ]; then
      echo "You have a working valid janus binary."
    else    # error status code, so uncompress from REPO package
      i=$( ls ${KVMDCACHE}/*.tar.xz | egrep janus )
      echo "-> Extracting package $i into /" >> $INSTLOG
      tar xfJ $i
    fi
  fi
} # end install-kvmd-pkgs

fix-udevrules() {
  if [[ $model == "400" ]]; then
    # rpi400 specific updates
    sed -i -e 's+rpi4 \%b+rpi400 \%b+g' /etc/udev/rules.d/99-kvmd.rules
    sed -i -e 's+\t\*) exit 1;;+\t"rpi400")\n\t\texit 0;;\n\t\*) exit 1;;+g' /usr/bin/kvmd-udev-hdmiusb-check
  else
    # for hdmiusb, replace %b with 1-1.4:1.0 in /etc/udev/rules.d/99-kvmd.rules
    sed -i -e 's+\%b+1-1.4:1.0+g' /etc/udev/rules.d/99-kvmd.rules
  fi

  printf "\n\n/etc/udev/rules.d/99-kvmd.rules\n\n"
  cat /etc/udev/rules.d/99-kvmd.rules
} # end fix-udevrules

enable-kvmd-svcs() {
  if [ $SERIAL -eq 1 ]; then
    # enable KVMD services but don't start them for v0 platforms
    echo "-> Enabling kvmd-nginx kvmd-webterm and kvmd services, but do not start them."
    systemctl enable kvmd-nginx kvmd-webterm kvmd kvmd-fix
  else
    # enable KVMD services but don't start them for v2 platforms
    echo "-> Enabling kvmd-nginx kvmd-webterm kvmd-otg and kvmd services, but do not start them."
    systemctl enable kvmd-nginx kvmd-webterm kvmd-otg kvmd kvmd-fix
  fi

  # in case going from CSI to USB, then disable kvmd-tc358743 service (in case it's enabled)
  if [[ $( echo $platform | grep usb | wc -l ) -eq 1 ]]; then
    systemctl disable --now kvmd-tc358743
  else
    systemctl enable kvmd-tc358743
  fi
} # end enable-kvmd-svcs

build-ustreamer() {
  printf "\n\n-> Building ustreamer\n\n"
  # Install packages needed for building ustreamer source
  echo "apt install -y build-essential libevent-dev libjpeg-dev libbsd-dev libraspberrypi-dev libgpiod-dev libsystemd-dev"
  apt install -y build-essential libevent-dev libjpeg-dev libbsd-dev libraspberrypi-dev libgpiod-dev libsystemd-dev > /dev/null

  KERNELVER=$( uname -r | cut -d'.' -f1,2 )
  case "$KERNELVER" in 
    "5.10")
      # Download ustreamer source and build it
      cd /tmp; rm -rf ustreamer
      #git clone --depth=1 https://github.com/pikvm/ustreamer
      ### Added on 03/13/22 -- use my fork of ustreamer 4.13 in case the ustreamer code gets updated to 5.0
      ### ustreamer 5.0 uses diferent method to perform hardware encoding (can't use OMX encoder anymore)
      git clone --depth=1 https://github.com/srepac/ustreamer

      cd ustreamer
      if [[ $( uname -m ) == "aarch64" || $( grep -i codename /etc/os-release | cut -d'=' -f2 ) == "bullseye" ]]; then
        # 64-bit OS -OR- bullseye (removed omx headers), so don't compile OMX support for ustreamer
        make WITH_OMX=0 WITH_GPIO=1 WITH_SETPROCTITLE=1 WITH_SYSTEMD=1
      else
        # hardware OMX support with 32-bit ONLY (non bullseye)
        make WITH_OMX=1 WITH_GPIO=1 WITH_SETPROCTITLE=1 WITH_SYSTEMD=1
      fi
      ;;
    "5.15")
      # Download ustreamer 5.x source and build it
      cd /tmp; rm -rf ustreamer-m2m/
      wget https://github.com/pikvm/ustreamer/archive/refs/heads/m2m.zip 2> /dev/null
      unzip m2m.zip
      cd ustreamer-m2m/

      make WITH_GPIO=1 WITH_SYSTEMD=1
      ;;
    *)
      echo "Kernel version ${KERNELVER} is not 5.10 or 5.15.  Exiting."
      exit 1
      ;;
  esac

  make install
  # kvmd service is looking for /usr/bin/ustreamer
  ln -sf /usr/local/bin/ustreamer /usr/bin/
  ln -sf /usr/local/bin/ustreamer-dump /usr/bin/

  echo -n "ustreamer version/features: "; ustreamer -v && ustreamer --features
} # end build-ustreamer

build-wiringpi() {
  printf "\n\n-> Building wiringpi from source\n\n"

  cd /tmp; rm -rf WiringPi
  git clone https://github.com/WiringPi/WiringPi.git
  cd WiringPi
  ./build

  gpio -v
} # end build-wiringpi

install-dependencies() {
  echo
  echo "-> Installing dependencies for pikvm"

  apt-get update > /dev/null
  for i in nginx python3 net-tools bc expect v4l-utils iptables vim dos2unix screen tmate nfs-common gpiod ffmpeg dialog iptables dnsmasq git
  do
    echo "apt-get install -y $i"
    apt-get install -y $i > /dev/null
  done

  install-python-packages

  # webterm
  if [ ! -e /usr/bin/ttyd ]; then
    if [[ $( uname -m ) == "aarch64" || $( grep -i codename /etc/os-release | cut -d'=' -f2 ) == "bullseye" ]]; then
      ### 20220218: libwesockets is required for ttyd -- it's better to compile for all versions
      ### ... than to use install deb packages for 32-bit buster and compile for all others
      ### ... Compiling for all will always result in the most up-to-date ttyd version at time of install

      #Install libwebsockets manually ... this did not work for all OS's, so I reverted the change
#      echo "-> Building libwebsockets from source ..."
#      cd /tmp
#      git clone https://libwebsockets.org/repo/libwebsockets
#      cd libwebsockets
#      mkdir build
#      cd build
#      cmake -DLWS_MAX_SMP=1 -DLWS_WITHOUT_EXTENSIONS=0 -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" ..
#      make && make install

      ### 20220215: build ttyd if running on 64-bit OS or any version of bullseye
      ### 20220218: build ttyd for all OS
#      echo "-> Building ttyd (webterm) from source ..."
#      cd /tmp; rm -rf ttyd
#      apt-get install -y build-essential cmake git libjson-c-dev libwebsockets-dev
#      git clone https://github.com/tsl0922/ttyd.git
#      cd ttyd && mkdir build && cd build
#      cmake ..
#      make && make install
#      cp /usr/local/bin/ttyd /usr/bin/

      case $( uname -m ) in
        "aarch64")
          ARCH="arm64";;    # 64-bit bullseye
        "armv7l")
          ARCH="armhf";;    # 32-bit bullseye
        "armv6l")
          ARCH="armel";;    # any zero w 1st gen running bullseye
        *)
          echo "Unsupported architecture.  Exiting."; exit 1;;
      esac

      ### added on 03/28/22 -- building ttyd didn't work as expected so we're installing ttyd from deb package.
      ### install the relevant debian pkg based on architecture as above
      cd /tmp; wget http://ftp.us.debian.org/debian/pool/main/t/ttyd/ttyd_1.6.3-3~bpo11+1_${ARCH}.deb 2> /dev/null
      dpkg -i ttyd_1.6.3-3~bpo11+1_${ARCH}.deb

    else    # raspbian buster requires more dependencies as per below
      ### 20220215 issue: ttyd won't compile on buster so use the manual download of deb packages and install
      ### required dependent packages for ttyd ###
      cd /tmp
      wget http://ftp.us.debian.org/debian/pool/main/libe/libev/libev4_4.33-1_armhf.deb 2> /dev/null
      dpkg -i libev4_4.33-1_armhf.deb
      wget http://ftp.us.debian.org/debian/pool/main/j/json-c/libjson-c5_0.15-2_armhf.deb 2> /dev/null
      dpkg -i libjson-c5_0.15-2_armhf.deb
      wget http://ftp.us.debian.org/debian/pool/main/libu/libuv1/libuv1_1.40.0-2_armhf.deb 2> /dev/null
      dpkg -i libuv1_1.40.0-2_armhf.deb
      wget http://ftp.us.debian.org/debian/pool/main/t/ttyd/ttyd_1.6.3-3~bpo11+1_armhf.deb 2> /dev/null
      dpkg -i ttyd_1.6.3-3~bpo11+1_armhf.deb
    fi
  fi

  echo
  echo -n "ttyd version: "; ttyd -v

  if [ ! -e /usr/bin/ustreamer ]; then
    build-ustreamer
  fi

  # added on 03/01/2022 1000 PDT
  build-wiringpi
} # end install-dependencies

python-pkg-dir() {
  # create quick python script to show where python packages need to go
  cat << MYSCRIPT > /tmp/syspath.py
#!$(which python)
import sys
print (sys.path)
MYSCRIPT

  chmod +x /tmp/syspath.py

  #PYTHONDIR=$( /tmp/syspath.py | grep packages | sed -e 's/, /\n/g' -e 's/\[//g' -e 's/\]//g' -e "s+'++g" | tail -1 )
  ### changed on 02/22/22 2050 PDT
  PYTHONDIR=$( /tmp/syspath.py | sed 's/, /\n/g' | cut -d"'" -f2 | grep packages | tail -1 )
} # end python-pkg-dir

fix-nginx-symlinks() {
  # disable default nginx service since we will use kvmd-nginx instead
  echo
  echo "-> Disabling nginx service, so that we can use kvmd-nginx instead"
  systemctl disable --now nginx

  # setup symlinks
  echo
  echo "-> Creating symlinks for use with kvmd python scripts"
  if [ ! -e /usr/bin/nginx ]; then ln -s /usr/sbin/nginx /usr/bin/; fi
  if [ ! -e /usr/sbin/python ]; then ln -s /usr/bin/python3 /usr/sbin/python; fi
  if [ ! -e /usr/bin/iptables ]; then ln -s /usr/sbin/iptables /usr/bin/iptables; fi
  if [ ! -e /opt/vc/bin/vcgencmd ]; then mkdir -p /opt/vc/bin/; ln -s /usr/bin/vcgencmd /opt/vc/bin/vcgencmd; fi

  python-pkg-dir

  if [ ! -e $PYTHONDIR/kvmd ]; then
    ln -s /usr/lib/python3.9/site-packages/kvmd* ${PYTHONDIR}
  fi
} # end fix-nginx-symlinks

fix-webterm() {
  echo
  echo "-> Creating kvmd-webterm homedir"
  mkdir -p /home/kvmd-webterm
  chown kvmd-webterm /home/kvmd-webterm
  ls -ld /home/kvmd-webterm
} # end fix-webterm

create-kvmdfix() {
  # Create kvmd-fix service and script
  cat <<ENDSERVICE > /lib/systemd/system/kvmd-fix.service
[Unit]
Description=KVMD Fixes
After=network.target network-online.target nss-lookup.target
Before=kvmd.service

[Service]
User=root
Type=simple
ExecStart=/usr/bin/kvmd-fix

[Install]
WantedBy=multi-user.target
ENDSERVICE

  cat <<SCRIPTEND > /usr/bin/kvmd-fix
#!/bin/bash
# Written by @srepac
# 1.  Properly set group ownership of /dev/gpio*
# 2.  fix /dev/kvmd-video symlink to point to /dev/video0
#
### These fixes are required in order for kvmd service to start properly
#
set -x
chgrp gpio /dev/gpio*
ls -l /dev/gpio*

ls -l /dev/kvmd-video
rm /dev/kvmd-video
ln -s video0 /dev/kvmd-video
SCRIPTEND

  chmod +x /usr/bin/kvmd-fix
} # end create-kvmdfix

set-ownership() {
  # set proper ownership of password files and kvmd-webterm homedir
  cd /etc/kvmd
  chown kvmd:kvmd htpasswd
  chown kvmd-ipmi:kvmd-ipmi ipmipasswd
  chown kvmd-vnc:kvmd-vnc vncpasswd
  chown kvmd-webterm /home/kvmd-webterm

  # add kvmd user to video group (this is required in order to use CSI bridge with OMX and h264 support)
  usermod -a -G video kvmd

  # add kvmd to dialout group (required for xh_hk4401 use per @bobiverse)
  usermod -aG dialout kvmd
} # end set-ownership

check-kvmd-works() {
  # check to make sure kvmd -m works before continuing
  invalid=1
  while [ $invalid -eq 1 ]; do
    kvmd -m | tee -a $LOGFILE
    read -p "Did kvmd -m run properly?  [y/n] " answer
    case $answer in
      n|N|no|No)
        echo "Please install missing packages as per the kvmd -m output in another ssh/terminal."
        ;;
      y|Y|Yes|yes)
        invalid=0
        ;;
      *)
        echo "Try again.";;
    esac
  done
} # end check-kvmd-works

start-kvmd-svcs() {
  #### start the main KVM services in order ####
  # 1. nginx is the webserver
  # 2. kvmd-otg is for OTG devices (keyboard/mouse, etc..)
  # 3. kvmd is the main daemon
  systemctl restart kvmd-nginx kvmd-otg kvmd-webterm kvmd kvmd-fix
} # end start-kvmd-svcs

fix-motd() {
  if [ $( grep pikvm /etc/motd | wc -l ) -eq 0 ]; then
    cp /etc/motd /etc/motd.orig; rm /etc/motd

    printf "
         ____  ____  _        _  ____     ____  __
        |  _ \|  _ \(_)      | |/ /\ \   / /  \/  |
        | |_) | |_) | |  __  | ' /  \ \ / /| |\/| |  software by @mdevaev
        |  _ <|  __/| | (__) | . \   \ V / | |  | |
        |_| \_\_|   |_|      |_|\_\   \_/  |_|  |_|  port by @srepac

    Welcome to Raspbian-KVM - Open Source IP-KVM based on Raspberry Pi
    ____________________________________________________________________________

    To prevent kernel messages from printing to the terminal use \"dmesg -n 1\".

    To change KVM password use command \"kvmd-htpasswd set admin\".

    Useful links:
      * https://pikvm.org

" > /etc/motd

    cat /etc/motd.orig >> /etc/motd
  fi
} # end fix-motd

restore-configs() {
  printf "\n-> Restoring config files\n"
  # Restore passwd files used by PiKVM
  cp /etc/kvmd/htpasswd.save /etc/kvmd/htpasswd 2> /dev/null
  cp /etc/kvmd/ipmipasswd.save /etc/kvmd/ipmipasswd 2> /dev/null
  cp /etc/kvmd/vncpasswd.save /etc/kvmd/vncpasswd 2> /dev/null

  # Restore webUI name and overrides
  cp /etc/kvmd/meta.yaml.save /etc/kvmd/meta.yaml 2> /dev/null
  cp /etc/kvmd/override.yaml.save /etc/kvmd/override.yaml 2> /dev/null
  cp /etc/kvmd/web.css.save /etc/kvmd/web.css 2> /dev/null

  # Restore Janus configs
  #cp /etc/kvmd/janus/janus.cfg.save /etc/kvmd/janus/janus.cfg 2> /dev/null

  # Restore sudoers.d/99_kvmd and custom_commands
  cp /etc/sudoers.d/99_kvmd.save /etc/sudoers.d/99_kvmd 2> /dev/null
  cp /etc/sudoers.d/custom_commands.save /etc/sudoers.d/custom_commands 2> /dev/null
} # end restore-configs

change-pointer() {   # change default pointer of blue dot to crosshair
  if [ $( grep -cw crosshair /etc/kvmd/web.css ) -ne 1 ]; then

    cat <<POINTER >> /etc/kvmd/web.css
div.stream-box-mouse-enabled {
    cursor: crosshair !important;
}
POINTER

  fi
} # end change-pointer to crosshair


### MAIN STARTS HERE ###
# Install is done in two parts
# First part requires a reboot in order to create kvmd users and groups
# Second part will start the necessary kvmd services
# added option to re-install by adding -f parameter (for use as platform switcher)
### changed 02/25/2022 - if /usr/bin/kvmd doesn't exist OR -force install is selected, then run Part 1 ###
if [[ ! -e /usr/bin/kvmd || "$1" == "-f" ]]; then
  printf "\nRunning part 1 of PiKVM installer v$VER script for Raspbian by @srepac\n" | tee -a $LOGFILE
  get-packages | tee -a $LOGFILE
  SERIAL=0; get-platform
  boot-files | tee -a $LOGFILE
  install-kvmd-pkgs | tee -a $LOGFILE
  create-override | tee -a $LOGFILE
  gen-ssl-certs | tee -a $LOGFILE
  fix-udevrules | tee -a $LOGFILE
  install-dependencies | tee -a $LOGFILE
  otg-devices | tee -a $LOGFILE
  create-kvmdfix | tee -a $LOGFILE
  enable-kvmd-svcs | tee -a $LOGFILE
  printf "\n\nReboot is required to create kvmd users and groups.\nPlease re-run this script after reboot to complete the install.\n"

  # Ask user to press CTRL+C before reboot or ENTER to proceed with reboot
  press-enter
  reboot

else

  printf "\nRunning part 2 of PiKVM installer v$VER script for Raspbian by @srepac\n" | tee -a $LOGFILE

  ### run these to make sure kvmd users are created ###
  echo "==> Ensuring KVMD users and groups ..." | tee -a $LOGFILE
  systemd-sysusers /usr/lib/sysusers.d/kvmd.conf  | tee -a $LOGFILE
  systemd-sysusers /usr/lib/sysusers.d/kvmd-webterm.conf | tee -a $LOTFILE

  fix-nginx-symlinks | tee -a $LOGFILE
  fix-webterm | tee -a $LOGFILE
  fix-motd | tee -a $LOGFILE
  set-ownership | tee -a $LOGFILE
  check-kvmd-works
  restore-configs | tee -a $LOGFILE
  change-pointer
  start-kvmd-svcs | tee -a $LOGFILE

  printf "\nCheck kvmd devices\n\n" | tee -a $LOGFILE
  ls -l /dev/kvmd* | tee -a $LOGFILE
  printf "\nYou should see devices for keyboard, mouse, and video.\n" | tee -a $LOGFILE

  printf "\nPoint a browser to https://$(hostname)\nIf it doesn't work, then reboot one last time.\nPlease make sure kvmd services are running after reboot.\n"
fi

# Fix paste-as-keys and disable ATX if running python 3.7
if [[ "${PYTHONVER}" == "3.7" ]]; then
  sed -i -e 's/reversed//g' /usr/lib/python3.9/site-packages/kvmd/keyboard/printer.py

  sed -i -e 's/    msd:$/    atx:\n        type: disabled\n    msd:/g' /etc/kvmd/override.yaml

  systemctl restart kvmd-nginx kvmd
fi

# If /var/lib/kvmd/msd is mounted, then remove msd: type: disabled lines in /etc/kvmd/override.yaml
if [ $( mount | grep -cw /var/lib/kvmd/msd ) -eq 1 ]; then
  sed -i -e 's/    msd:$        type: disabled$//g' /etc/kvmd/override.yaml
fi

# download pistat, pi-temp, and pikvm-info script into /usr/local/bin/
wget https://kvmnerds.com/RPiKVM/pistat -O /usr/local/bin/pistat > /dev/null 2> /dev/null
wget https://kvmnerds.com/RPiKVM/pi-temp -O /usr/local/bin/pi-temp > /dev/null 2> /dev/null
wget https://kvmnerds.com/RPiKVM/pikvm-info -O /usr/local/bin/pikvm-info > /dev/null 2> /dev/null
chmod +x /usr/local/bin/pi*

# required for pikvm-info to run properly as it is looking for vcgencmd in /usr/local/bin/
# this uses the correct vcgencmd binary for the running 32/64-bit OS
rm -f /opt/vc/bin/vcgencmd; ln -sf /usr/bin/vcgencmd /opt/vc/bin/vcgencmd
ln -sf /opt/vc/bin/vcgencmd /usr/local/bin/

# fix symlink of /bin/sh to bash not dash in raspbian
ln -sf bash /bin/sh

echo "Raspbian pikvm installer script completed on $( date )" | tee -a $LOGFILE
