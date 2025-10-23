#!/bin/sh
# Initialize Default user Script

username="$1"
grpname="$username"
grpid=1000

if [ -x /sbin/apk ]; then

    # Alpine default distribution does not contains required packages
    pkgs_to_install=""
    apk info 2>/dev/null | grep shadow >/dev/null || pkgs_to_install="$pkgs_to_install shadow"
    apk info 2>/dev/null | grep sudo >/dev/null || pkgs_to_install="$pkgs_to_install sudo"
    apk info 2>/dev/null | grep openssl >/dev/null || pkgs_to_install="$pkgs_to_install openssl"
    [ -z "$pkgs_to_install" ] || {
        apk update
        apk --no-cache add $pkgs_to_install
    }

    # configure sudo
    grep sudo /etc/group || /usr/sbin/addgroup --gid 65530 sudo
    sed -i 's/# *%sudo/%sudo/' /etc/sudoers

    # Create user
    /usr/sbin/addgroup --gid $grpid $grpname
    /usr/sbin/adduser --disabled-password --gecos '' --uid 1000 -G $grpname  $username
    /usr/sbin/adduser $username sudo

else

    # Ubuntu distributions
    # release >ubuntu-23 already has user ubuntu with uid:gid set to 1000:1001
    if /usr/bin/id -u ubuntu >/dev/null 2>&1; then
        /usr/sbin/deluser --remove-home ubuntu >/dev/null
    fi
    grep ':1000:' /etc/group >/dev/null && grpid=1001
    /usr/sbin/addgroup --gid $grpid $grpname
    /usr/sbin/adduser --quiet --disabled-password --gecos '' --uid 1000 --gid $grpid $username
    /usr/sbin/usermod -aG sudo $username

fi

# Initialize user password:
echo "Please create password for user $username"
userencpass="`/usr/bin/openssl passwd -1`"
/usr/sbin/usermod --password $userencpass $username
