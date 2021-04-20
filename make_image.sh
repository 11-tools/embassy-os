#!/bin/bash
OS=$(uname)
OS_VERSION=$(uname -r)
UNAME_M=$(uname -m)
ARCH=$(uname -m)
arch=$(uname -m)

if [[ $arch == armv7l ]]; then
    dev_target="target"
else
    dev_target="target/armv7-unknown-linux-musleabihf"
fi

mv buster.img embassy.img
product_key=$(cat product_key)
root_mountpoint="/mnt/start9-${product_key}-root"
boot_mountpoint="/mnt/start9-${product_key}-boot"
mkdir -p "${root_mountpoint}"
mkdir -p "${boot_mountpoint}"

report() {
    echo OS:
    echo "$OS" | awk '{print tolower($0)}'
    echo OS_VERSION:
    echo "$OS_VERSION" | awk '{print tolower($0)}'
    echo UNAME_M:
    echo "$UNAME_M" | awk '{print tolower($0)}'
    echo ARCH:
    echo "$ARCH" | awk '{print tolower($0)}'
    echo OSTYPE:
    echo "$OSTYPE" | awk '{print tolower($0)}'
}

checkraspi(){
    echo 'Checking Raspi'
    if [ -e /etc/rpi-issue ]; then
    echo "- Original Installation"
    cat /etc/rpi-issue
    fi
    if [ -e /usr/bin/lsb_release ]; then
    echo "- Current OS"
    lsb_release -irdc
    fi
    echo "- Kernel"
    uname -r
    echo "- Model"
    cat /proc/device-tree/model && echo
    echo "- hostname"
    hostname
    echo "- Firmware"
    /opt/vc/bin/vcgencmd version
}

checkbrew() {
    if hash brew 2>/dev/null; then
        brew install awk git curl
        brew install haskell-stack
        #curl -sSL https://get.haskellstack.org/ | sh
        echo
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        checkbrew
    fi
}

if [[ "$OSTYPE" == "linux"* ]]; then
    #CHECK APT
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        if hash apt 2>/dev/null; then
            if hash losetup 2>/dev/null; then
                loopdev=$(losetup -f -P embassy.img --show)
            else
                sudo apt-get install losetup curl haskell-stack
                stack upgrade --binary-only
            fi
        fi
    fi
    if [[ "$OSTYPE" == "linux-musl" ]]; then
        if hash apk 2>/dev/null; then
            if hash losetup 2>/dev/null; then
                loopdev=$(losetup -f -P embassy.img --show)
            else
                sudo apk add losetup curl haskell-stack
                stack upgrade --binary-only
            fi
        fi
    fi
    if [[ "$OSTYPE" == "linux-arm"* ]]; then
        if hash apt 2>/dev/null; then
            if hash losetup 2>/dev/null; then
                loopdev=$(losetup -f -P embassy.img --show)
            else
                sudo apt install losetup curl haskell-stack
                stack upgrade --binary-only
            fi
        fi
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
        if hash hdiutil 2>/dev/null; then
            checkbrew
            echo
        else
            echo
        fi
fi

if [[ "$OSTYPE" == "linux"* ]]; then
    mount "${loopdev}p2" "${root_mountpoint}"
    mount "${loopdev}p1" "${boot_mountpoint}"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if hash hdiutil 2>/dev/null; then
        hdiutil mount embassy.img -mountpoint $boot_mountpoint
    fi
fi

mkdir -p "${root_mountpoint}/root/agent"
mkdir -p "${root_mountpoint}/etc/docker"
mkdir -p "${root_mountpoint}/home/pi/.ssh"
echo -n "" > "${root_mountpoint}/home/pi/.ssh/authorized_keys"
git clone --depth 1 https://github.com/Start9Labs/embassy-os.git /home/pi/
chown -R pi:pi "${root_mountpoint}/home/pi/.ssh"
echo "${product_key}" > "${root_mountpoint}/root/agent/product_key"
echo -n "start9-" > "${root_mountpoint}/etc/hostname"
echo -n "${product_key}" | shasum -t -a 256 | cut -c1-8 >> "${root_mountpoint}/etc/hostname"
cat "${root_mountpoint}/etc/hosts" | grep -v "127.0.1.1" > "${root_mountpoint}/etc/hosts.tmp"
echo -ne "127.0.1.1\tstart9-" >> "${root_mountpoint}/etc/hosts.tmp"
echo -n "${product_key}" | shasum -t -a 256 | cut -c1-8 >> "${root_mountpoint}/etc/hosts.tmp"
mv "${root_mountpoint}/etc/hosts.tmp" "${root_mountpoint}/etc/hosts"
cp agent/dist/agent "${root_mountpoint}/usr/local/bin/agent"
chmod 700 "${root_mountpoint}/usr/local/bin/agent"
cp "appmgr/${dev_target}/release/appmgr" "${root_mountpoint}/usr/local/bin/appmgr"
chmod 700 "${root_mountpoint}/usr/local/bin/appmgr"
cp "lifeline/${dev_target}/release/lifeline" "${root_mountpoint}/usr/local/bin/lifeline"
chmod 700 "${root_mountpoint}/usr/local/bin/lifeline"
cp docker-daemon.json "${root_mountpoint}/etc/docker/daemon.json"
cp setup.sh "${root_mountpoint}/root/setup.sh"
chmod 700 "${root_mountpoint}/root/setup.sh"
cp setup.service "${root_mountpoint}/etc/systemd/system/setup.service"
ln -s  /etc/systemd/system/setup.service "${root_mountpoint}/etc/systemd/system/getty.target.wants/setup.service"
cp lifeline/lifeline.service "${root_mountpoint}/etc/systemd/system/lifeline.service"
cp agent/config/agent.service "${root_mountpoint}/etc/systemd/system/agent.service"

if [[ "$OSTYPE" == "linux"* ]]; then
    umount "${loopdev}p2" "${root_mountpoint}"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if hash hdiutil 2>/dev/null; then
        umount "${root_mountpoint}"
        hdiutil mount embassy.img -mountpoint $boot_mountpoint
    fi
fi

echo -n "" > "${boot_mountpoint}/ssh"
cat "${boot_mountpoint}/config.txt" | grep -v "dtoverlay=" > "${boot_mountpoint}/config.txt.tmp"
echo "dtoverlay=pwm-2chan" >> "${boot_mountpoint}/config.txt.tmp"
mv "${boot_mountpoint}/config.txt.tmp" "${boot_mountpoint}/config.txt"
umount "${boot_mountpoint}"
rm -r "${boot_mountpoint}"

if [[ "$OSTYPE" == "linux"* ]]; then
    umount "${boot_mountpoint}"
    rm -r "${boot_mountpoint}"
    losetup -d ${loopdev}
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if hash hdiutil 2>/dev/null; then
        umount "${boot_mountpoint}"
        #hdiutil mount embassy.img -mountpoint $boot_mountpoint
    fi
fi
echo "DONE! Here is your EmbassyOS key: ${product_key}"