# gentoo-inst.sh - Install Gentoo.
# Use this script to automate and speed-up the Gentoo installation process.
# Remember to change the default values, if necessary, and to check whether the
# stage 3 file still exists using the urlok function.

# disk device in which to put the gentoo installation
diskdev='/dev/sda'

# size of the swap partition in a format suitable for fdisk
swapsize='8G'

# mirror of the stage 3 file (https only)
stagemirr='gentoo.mirror.garr.it'

# type of the stage 3 file (i.e. file name without extension, date, or time)
stagetype='stage3-amd64-openrc'

# mirrors for portage
mirrors="https://mirror.kumi.systems/gentoo/ \
http://mirror.kumi.systems/gentoo/ \
rsync://mirror.kumi.systems/gentoo/ \
https://ftp.uni-stuttgart.de/gentoo-distfiles/ \
http://ftp.uni-stuttgart.de/gentoo-distfiles/ \
ftp://ftp.uni-stuttgart.de/gentoo-distfiles/ \
https://gentoo.mirror.garr.it/ \
http://gentoo.mirror.garr.it/ \
https://mirror.init7.net/gentoo/ \
http://mirror.init7.net/gentoo/ \
rsync://mirror.init7.net/gentoo/"

# timezone
timezone='Europe/Rome'

# locales (the first is used as system language)
locales='en_GB.UTF-8 UTF-8
en_US.UTF-8 UTF-8
it_IT.UTF-8 UTF-8'

# info about new user
username='edo'
userfull='Edoardo La Greca'

# -- BEGIN INTERNAL FUNCTIONS -- #

# merge the current USE flags with another USE flag
# e.g.: mergeuse -kde (disables the kde USE flag)
# e.g.: mergeuse networkmanager (enables the networkmanager USE flag)
# if the given flag was not present, add it
# if the given flag is already present and has opposite mode (enabled or disabled), invert the mode
# if the given flag is already present and has the same mode (enabled or disabled), do nothing
# if the USE variable is not defined, define it with the given flag
mergeuse() {
	makeconf='/etc/portage/make.conf'
	flag="$1"
	mode=`echo $flag | egrep -o '^-?'`
	flag=`echo $flag | sed "s/^$mode//"`

	if [ ! -r $makeconf ]
	then
		touch $makeconf
	fi

	if ! egrep '^USE=' $makeconf
	then
		echo "USE=\"\"" >>$makeconf
	fi

	oldusefull=`tr -d '\\' <$makeconf | tr '\n' ' ' | sed -E 's/[[:space:]]{2,}/ /' | egrep -o "^USE=(\"|')[^[:cntrl:]]*(\"|')"`
	olduse=`echo $oldusefull | sed "s/^USE=//;s/'//g;s/\"//g"`
	match=`echo "$olduse" | egrep -o "(^|[[:space:]])(-|+)?$flag([[:space:]]|\$)"`

	if [ -z "$match" ]
	then
		newuse="$olduse $mode$flag"
	else
		newuse=`echo $olduse | sed "s/$match/$mode$flag/"`
	fi

	newusefull="USE=\"$newuse\""
	sed -i "s/$oldusefull/$newusefull/" $makeconf
}

# find the partition UUID of the specified partition device (e.g. /dev/sda2)
partuuid() {
	partdev="$1"
	blkid | grep "^$partdev:" | grep -o 'PARTUUID=".*"' | sed 's/^PARTUUID="//;s/"$//'
}

# -- END INTERNAL FUNCTIONS -- #
# -- BEGIN UTILITY FUNCTIONS -- #

# compose the latest stage 3 file's url
stageurl() {
	baseurl="https://${stagemirr}/releases/amd64/autobuilds"
	innerpath=`curl -Ss "${baseurl}/latest-${stagetype}.txt" | grep -m 1 "$stagetype" | awk '{ print $1 }'`
	echo "${baseurl}/${innerpath}"
}

# check whether an http(s) url points to an existing resource
urlok() {
	url="$1"
	sc=`curl -sI "$url" | grep HTTP | awk '{ print $2 }'`
	echo "$sc" | egrep '^2[[:digit:]]{2}'
}

# -- END UTILITY FUNCTIONS -- #
# -- BEGIN STEP FUNCTIONS -- #

# check root access
rootok() {
	uid=`id -u`
	if [ $uid -ne 0 ]
	then
		echo 'run as root' >&2
		return 1
	fi
}

# check connection
connok() {
	if ! ping -c 3 1.1.1.1 >/dev/null
	then
		echo 'no internet connection' >&2
		return 1
	fi
}

# ask confirmation for disk
diskok() {
	printf "is $diskdev the correct disk? (y/N) "
	read ans
	echo $ans | egrep -i '^y(es)?$' >/dev/null
	if [ $? -ne 0 ]
	then
		echo "$diskdev is incorrect" >&2
		return 1
	fi
}

# partition disk
mkparts() {
	partinfo="o
g
n
1

+1G
n
2

+$swapsize
n
3


t
1
1
t
2
19
t
3
23
w
"
	echo "$partinfo" | fdisk $diskdev -w always -W always
	if [ $? -ne 0 ]
	then
		echo 'an error occurred while partitioning the disk' >&2
		return 1
	fi
}

# create filesystems and activate swap
mkfsys() {
	e=0

	mkfs.vfat -F 32 $esp
	test $? -ne 0 && e=1

	mkswap $swap
	test $? -ne 0 && e=1

	swapon $swap
	test $? -ne 0 && e=1

	mkfs.ext4 $rootfs
	test $? -ne 0 && e=1

	if [ $e -ne 0 ]
	then
		echo 'could not create filesystem for one or more partitions' >&2
	fi

	return $e
}

# mount root
mountroot() {
	mkdir -p $rootdir
	mount $rootfs $rootdir
	mkdir -p $rootdir/efi
}

# download and install stage file
inststagefile() {
	url=`stageurl`
	curl -O $url
	if [ $? -ne 0 ]
	then
		echo 'failed to download stage file' >&2
		return 1
	fi
	stagefile=`basename $url`
	mv $stagefile $rootdir
	wd=$PWD
	cd $rootdir
	tar xpvf $stagefile --xattrs-include='*.*' --numeric-owner
	e=$?
	cd $wd
	if [ $e -ne 0 ]
	then
		echo 'failed to extract stage file' >&2
		return 1
	fi
}

# configure compile options
compileopts() {
	# don't
	:
}

# pre-chroot
prechroot() {
	e=0

	cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
	test $? -ne 0 && e=1
	mount --types proc /proc $rootdir/proc
	test $? -ne 0 && e=1
	mount --rbind /sys $rootdir/sys
	test $? -ne 0 && e=1
	mount --rbind /dev $rootdir/dev
	test $? -ne 0 && e=1
	mount --bind /run $rootdir/run
	test $? -ne 0 && e=1

	return $e
}

# post-chroot
postchroot() {
	. /etc/profile
	PS1="(chroot) $PS1"
	export PS1
	mount $esp /efi
}

# configure portage
confptg() {
	until emerge --sync --quiet
	do
		printf 'failed to sync emerge, retry? (Y/n) '
		read ans
		echo $ans | egrep -i '^no?$' >/dev/null
		if [ $? -eq 0 ]
		then
			return 1
		fi
	done

	echo "GENTOO_MIRRORS=\"$mirrors\"" >>/etc/portage/make.conf
	# skip news reading
	# skip profile selection
	# skip binary package host
	# skip USE variable configuration, including CPU_FLAGS_* and VIDEO_CARDS
	# skip ACCEPT_LICENSE variable configuration
	# skip @world set updating
	mkdir -p /etc/portage/package.license
	touch /etc/portage/package.license/kernel
	echo 'sys-kernel/linux-firmware linux-fw-redistributable' >>/etc/portage/package.license/kernel
}

# set timezone
settz() {
	echo "$timezone" >/etc/timezone
	emerge --config sys-libs/timezone-data
}

# configure locales
setlocales() {
	echo "$locales" >/etc/locale.gen
	locale-gen
	if [ $? -ne 0 ]
	then
		echo 'unable to generate locales' >&2
		return 1
	fi
	echo "LANG=\"`echo "$locales" | head -n 1 | awk '{print $1}'`\"" >>/etc/env.d/02locale
	echo "LC_COLLATE=\"C.UTF-8\"" >>/etc/env.d/02locale
}

# download and install firmware
dlfw() {
	emerge sys-kernel/linux-firmware
}

# kernel configuration and compilation
kernconf() {
	echo 'sys-kernel/installkernel grub' >>/etc/portage/package.use/installkernel
	echo 'sys-kernel/installkernel dracut' >>/etc/portage/package.use/installkernel
	emerge sys-kernel/installkernel
	test $? -ne 0 && return 1

	# use distribution kernel
	emerge sys-kernel/gentoo-kernel-bin
	test $? -ne 0 && return 1
	# skip signing (both kernel modules and kernel image)

	# add dist-kernel USE flag
	mergeuse 'dist-kernel'
}

# fill /etc/fstab
fstabconf() {
	b=`blkid`
	if [ $? -ne 0 ]
	then
		echo 'unable to retrieve partition info' >&2
		return 1
	fi

	# add /efi
	uuid=`partuuid $esp`
	printf "PARTUUID=$uuid\t/efi\tvfat\tumask=0077\t0 2\n" >>/etc/fstab

	# add swap
	uuid=`partuuid $swap`
	printf "PARTUUID=$uuid\tnone\tswap\tsw\t0 0\n" >>/etc/fstab

	# add /
	uuid=`partuuid $rootfs`
	printf "PARTUUID=$uuid\t/\text4\tdefaults\t0 1\n" >>/etc/fstab
}

# configure networking
netconf() {
	echo edo-pc >/etc/hostname

	# use dhcpcd instead of netifrc
	# starting dhcpcd may fail as that service may already be running.
	# this is not a problem and the exit status of this function should
	# not be affected by it.
	emerge net-misc/dhcpcd && rc-update add dhcpcd default
	e=$?
	rc-service dhcpcd start
	return $e
}

# set up OpenRC
openrcconf() {
	# /etc/rc.conf
	if [ -f ./rc.conf ]
	then
		if ! diff ./rc.conf /etc/rc.conf
		then
			mv /etc/rc.conf /etc/rc.conf.bk
			cp ./rc.conf /etc
			return 0
		else
			echo 'the new ./rc.conf and the old /etc/rc.conf files are identical' >&2
			return 0
		fi
	else
		echo 'rc.conf does not exist or it is not a regular file, failed to set up OpenRC' >&2
		return 1
	fi

	# /etc/conf.d/hwclock
	#sed -i 's/#*clock=.*/clock="local"/' /etc/conf.d/hwclock
}

# set up a system logger
syslogger() {
	emerge app-admin/sysklogd && rc-update add sysklogd default
}

# install a cron daemon
crondmon() {
	emerge sys-process/cronie && rc-update add cronie default
}

# add file indexing
fileindexing() {
	emerge sys-apps/mlocate
}

# enable the SSH daemon
sshdmon() {
	rc-update add sshd default
}

# add Bash completions
bashcompl() {
	#emerge app-shells/bash-completion
	:
}

# add time synchronization
timesync() {
	emerge net-misc/chrony && rc-update add chronyd default
}

# install the filesystem tools
fstools() {
	# already installed for ext4 as part of @world
	#emerge sys-fs/e2fsprogs
	:
}

# install networking tools
nettools() {
	# dhcpcd was already installed in netconf
	#emerge net-misc/dhcpcd
	emerge net-wireless/iw net-wireless/wpa_supplicant
}

# add a bootloader
bootld() {
	# set GRUB_PLATFORMS anyway to ensure compatibility with UEFI
	echo 'GRUB_PLATFORMS="efi-64"' >>/etc/portage/make.conf
	emerge --verbose sys-boot/grub
	if [ $? -ne 0 ]
	then
		echo 'unable to install grub' >&2
		return 1
	fi

	# make sure that the EFI system partition is mounted before installing
	mkdir -p /efi
	mount $esp /efi

	grub-install --efi-directory=/efi && grub-mkconfig -o /boot/grub/grub.cfg
}

# prompt for a new root password
rootpw() {
	passwd
}

# primpt for a new user
newusr() {
	useradd -c "$userfull" -G 'audio,cdrom,cron,floppy,usb,video,wheel' -m -s /bin/bash $username && passwd $username
}

# -- END STEP FUNCTIONS -- #

# part 1: before chroot
part1() {
	rootok
	connok
	diskok
	mkparts
	mkfsys
	mountroot
	inststagefile
	compileopts
	prechroot
}

#chroot $rootdir /bin/bash

# part 2: after chroot
part2() {
	postchroot
	confptg
	settz
	setlocales
	dlfw
	kernconf
	fstabconf
	netconf
	openrcconf
	syslogger
	crondmon
	fileindexing
	sshdmon
	bashcompl
	timesync
	fstools
	nettools
	bootld
	rootpw
	newusr
}

# disk partitions
esp="${diskdev}1"
swap="${diskdev}2"
rootfs="${diskdev}3"

# for part1
rootdir='/mnt/gentoo'

"$@"
