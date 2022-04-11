#!/bin/bash
# Written by @srepac    NEWER installer for Raspbian PiKVM -- uses mostly deb packages
# Filename:  pikvm-raspbian.sh
###
# This script performs the following:
#
#  1. Adds repo location for my precompiled deb packages for ustreamer, janus, webterm, kvmd-platform and kvmd
: ' The below lines are put into /etc/apt/sources.list.d/pikvm-raspbian.list file:
# new pikvm deb packages from srepac
deb [trusted=yes] https://kvmnerds.com/debian /
'
#  2. Sets up /boot/config.txt (proper gpu_mem based on board) and /etc/modules based on platform chosen.
#  3. Shows you command to install and will even run the install if -f option is passed in.
###
VERSION="1.0"
: ' As of 20220410 2330 PDT '
# CHANGELOG:
# 1.0  20220410  created script
###
usage() {
  echo "$0 [-f]   where -f performs the actual install, otherwise show command only"
  exit 1
} # end usage


error-checking() {
  WHOAMI=$( whoami )
  if [[ "$WHOAMI" != "root" ]]; then
    echo "$WHOAMI, you must be root to run this."
    exit 1
  fi

  case $1 in
    --help|-h)
      usage
      ;;
    --debug|-d)
      d_flag=1
      ;;
    --force|-f)
      f_flag=1
      echo "*** Forced install option selected"
      ;;
    --show-only|*)
      f_flag=0
      echo "*** ONLY Show commands to run"
      ;;
  esac

  OS=$( grep ^ID= /etc/os-release | cut -d'=' -f2 )
  case $OS in
    debian|raspbian|ubuntu)
      printf "+ OSID [ $OS ] is supported by installer.\n"
      ;;
    *)
      printf "+ OSID [ $OS ] is NOT supported by installer.  Exiting.\n"
      exit 1
      ;;
  esac
} # end error-checking


initialize() {
  SERIAL=0

  # Add custom entry in /etc/apt/sources.list.d/ so we can run apt install/update/upgrade/remove
  SOURCELIST="/etc/apt/sources.list.d/pikvm-raspbian.list"
  if [ ! -e $SOURCELIST ]; then
    printf "# new pikvm deb packages from srepac\ndeb [trusted=yes] https://kvmnerds.com/debian /\n" > $SOURCELIST
  else
    printf "+ $SOURCELIST already exists.\n\n"
  fi

  if [ ! -e /tmp/pacmanquery ]; then
    if [ ! -e /usr/local/bin/pikvm-info ]; then
      wget -O /usr/local/bin/pikvm-info https://kvmnerds.com/PiKVM/pikvm-info 2> /dev/null
      chmod +x /usr/local/bin/pikvm-info
    fi
    /usr/local/bin/pikvm-info > /dev/null 2>&1
  fi
} # end initialize


get-platform() {
  model=$( tr -d '\0' < /proc/device-tree/model | cut -d' ' -f3,4,5 | sed -e 's/ //g' -e 's/Z/z/g' -e 's/Model//' -e 's/Rev//g'  -e 's/1.[0-9]//g' )
  case $model in

    "zero2W"|"zero2")
      # force platform to only use v2-hdmi for zero2w
      platform="kvmd-platform-v2-hdmi-zero2w"
      export GPUMEM=96
      ;;

    "zeroW")
      # force platform to only use v2-hdmi for zerow
      platform="kvmd-platform-v2-hdmi-zerow"
      export GPUMEM=64
      ;;

    "3A"|"3APlus")
      platform="kvmd-platform-v2-hdmi-rpi4"     # use rpi4 platform which supports webrtc
      export GPUMEM=96
      ;;

    "3B"|"2B"|"2A"|"B"|"A")
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
      platform="kvmd-platform-v2-hdmiusb-rpi4"
      export GPUMEM=256
      ;;

    *)   ### default to use rpi4 platform image (this may also work with other SBCs with OTG)
      tryagain=1
      while [ $tryagain -eq 1 ]; do
        printf "Choose which capture device you will use:\n
  1 - USB dongle   32/64-bit
  2 - v2 CSI     32-bit only
  3 - V3 HAT     32-bit only\n"
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

  echo
  echo "Platform selected -> $platform"
  echo
} # end get-platform


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
} # end of necessary boot files


install-params() {
  # Determine Pi board, OS and bit version
  ARCH=$( uname -m )

  case $ARCH in
    aarch64)
      BITS=64bit
      # override board to rpi4 (this takes care of z2w, 3A+, 4B, 400, and CM4)
      board=rpi4
      platform=$( echo $platform | sed 's/zero2w/rpi4/g' )

      case $platform in
        kvmd-platform-v2-hdmiusb-rpi4)
          echo "USB HDMI Capture device selected is supported."
          ;;

        kvmd-platform-v2-hdmi-rpi4|kvmd-platform-v3-hdmi-rpi4)
          ## only thing required is /boot/config.txt entry and /etc/modules to load tc358743 support
          echo "CSI Capture device selected is supported."
          ;;

        *)
          echo "Unknown platform selected.  Exiting."; exit 1 ;;
      esac
    ;;

    armv7l)
      BITS=32bit
      # override board to rpi4 (this takes care of z2w, 3A+, 4B, 400, and CM4)
      board=rpi4
      platform=$( echo $platform | sed 's/zero2w/rpi4/g' )

      case $platform in
        kvmd-platform-v2-hdmiusb-rpi4)
          echo "USB HDMI Capture device selected is supported."
          ;;

        kvmd-platform-v2-hdmi-rpi4|kvmd-platform-v3-hdmi-rpi4)
          echo "CSI Capture device selected is supported."
          ;;

        *)
          echo "$BITS OS does NOT support capture device."; exit 1 ;;
      esac
      ;;

    armv6l)
      BITS=32bit
      board=zerow
      case $platform in
        kvmd-platform-v2-hdmi-zerow)
          echo "CSI Capture device selected is supported."
          ;;

        *)
          echo "$BITS OS does NOT support capture device."; exit 1 ;;
      esac
      ;;

    *)
      echo "Unknown machine architecture [ $ARCH ].  Exiting"; exit 1 ;;
  esac

  printf "\n-> Install instructions:\n"
  echo " platform:  $platform"
  echo " board:     $board"
  echo " ARCH:      $ARCH"
  echo " OS bits:   $BITS"
} # end install-params


get-installed() {
  printf "\n-> Getting list of installed packages...\n"
  apt update > /dev/null 2>&1

  ### show current installed
  if [ -e /tmp/pacmanquery ]; then
    if [ $( egrep 'kvmd|janus|ustreamer' /tmp/pacmanquery | wc -l ) -gt 0 ]; then
      printf "\nCurrent installed kvmd, janus, and ustreamer packages:\n"
      egrep 'kvmd|janus|ustreamer' /tmp/pacmanquery
    else
      echo "No kvmd, janus, or ustreamer packages currently installed."
    fi
  fi

  KVMDPKGS="/tmp/kvmd-packages"; /bin/rm -f $KVMDPKGS $KVMDPKGS.sorted
  apt-cache search ustreamer >> $KVMDPKGS
  apt-cache search janus >> $KVMDPKGS
  apt-cache search kvmd >> $KVMDPKGS
  cat $KVMDPKGS | sort -r -u > $KVMDPKGS.sorted

  echo
} # end get-installed


are-you-sure() {
  invalidinput=1
  while [ $invalidinput -eq 1 ]; do
    printf "\n*** Install PiKVM on this system.\n"
    read -p "Are you sure? [y/n] " SURE
    case $SURE in
      Y|y) invalidinput=0 ;;
      N|n) echo "Exiting."; exit 0 ;;
      *) echo "Invalid input. try again."; invalidinput=1 ;;
    esac
  done
} # end are-you-sure fn


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


show-commands() {
  # Setup commands to install other packages before the main kvmd package
  if [[ $board == "rpi4" && $BITS == "32bit" ]]; then
    OTHERS="apt install -y $( egrep "${BITS}|$platform" $KVMDPKGS.sorted | grep -v zerow | awk '{print $1}' | tr '\n' ' ' )"
  else
    OTHERS="apt install -y $( egrep "${BITS}|$platform" $KVMDPKGS.sorted | awk '{print $1}' | tr '\n' ' ' )"
  fi
  KVMD="$( egrep kvmd-raspbian $KVMDPKGS.sorted | awk '{print $1}' | tr '\n' ' ' )"

  # first install janus, ustreamer, platform, webterm, and lastly, kvmd-raspbian
  INSTALLCMD="$OTHERS $KVMD"

  printf "\n-> Copy/Paste below command to install PiKVM on your Debian-based system manually.\n"
  printf "\n${INSTALLCMD}\n"

  if [[ ${f_flag} -eq 1 ]]; then
    CALL are-you-sure
    ${INSTALLCMD}
  else
    printf "\n*** NOTE:  If you want the script to run the install command, then add -f option.\n"
  fi
} # end setup-commands


fixes() {  ### required fixes
  if [ ! -e /usr/bin/nginx ]; then ln -s /usr/sbin/nginx /usr/bin/; fi
  if [ ! -e /usr/sbin/python ]; then ln -s /usr/bin/python3 /usr/sbin/python; fi
  if [ ! -e /usr/bin/iptables ]; then ln -s /usr/sbin/iptables /usr/bin/iptables; fi
  if [ ! -e /opt/vc/bin/vcgencmd ]; then mkdir -p /opt/vc/bin/; ln -s /usr/bin/vcgencmd /opt/vc/bin/vcgencmd; fi
} # end fixes


otg-devices() {  # create otg devices
  modprobe libcomposite
  if [ ! -e /sys/kernel/config/usb_gadget/kvmd ]; then
    mkdir -p /sys/kernel/config/usb_gadget/kvmd/functions
    cd /sys/kernel/config/usb_gadget/kvmd/functions
    mkdir hid.usb0  hid.usb1  hid.usb2  mass_storage.usb0
  fi
} # end otg-device creation


CALL() {  ### show banner and run function passed in
  if [[ $d_flag -eq 1 ]]; then printf "\n --- function $1 ---\n"; fi
  $1
} #



### MAIN STARTS HERE ###
printf "Running new installer version $VERSION that uses deb packages\n\n"
## required in order to keep track of running kvmd processes and sockets
mkdir -p /run/kvmd
chown kvmd:kvmd /run/kvmd
chmod 775 /run/kvmd

if [ -e /usr/local/bin/rw ]; then rw; fi
error-checking $@
CALL initialize
CALL get-platform
CALL boot-files
CALL fixes
CALL otg-devices
CALL install-params
CALL get-installed
if [ $( grep -c 'port by @srepac' /etc/motd ) -eq 0 ]; then fix-motd; fi
CALL show-commands
if [ -e /usr/local/bin/ro ]; then ro; fi
