#!/bin/bash
#
# cab - CentOS OpenVZ Appliance Builder
# Support Redhat/CentOS 6.x/7.0
# Require : yum-utils
#

: ${TPM:="$(mktemp -d)"}
: ${ARCH_DEFAULTS:="$(uname -m)"}
: ${DISTRIB_DEFAULTS:="CentOS"}
: ${DISTRIB_VERSION_DEFAULTS:="6.5"}
: ${PACKAGE_RELEASE_DISTRIB:="centos-release"}
: ${VZ_CHROOT:="${TPM}/var/lib"}
: ${VZ_PKG_DIR:="${TPM}/pkg"}
: ${OUTPUT_DIR:="/tmp"}
: ${PACKAGES_LIST_FILE:="cab.pkglist"}
: ${YUM_REPO_FILE:="/etc/yum.repos.d/cab.repo"}
: ${MIRROR_DEFAULTS:="http://mirror.in2p3.fr/linux/${DISTRIB_DEFAULTS}/${DISTRIB_VERSION_DEFAULTS}/os/${ARCH_DEFAULTS}/"}


# Check run as root
[ "$(id -u)" != "0" ] && echo "This script must be run as root." && exit 1

err(){
	exitnum="$1"
	shift
	echo "$@" >&2
	exit $exitnum
}

usage(){
	echo -e "\nUsage:  cab command [OPTIONS]"
	echo -e "\tbuild <distrib> <distrib_version> <arch> <packages_list_file> [mirror]"
	echo -e "Example: cab build centos 6.5 x86_64 cab.pkglist\n"
}

_print(){
	echo -e "$1"
}

look_over_pkg_list(){
	[ ! -f ${PACKAGES_LIST_FILE} ] && _print "${PACKAGES_LIST_FILE} is missing" && exit 1
	while read _pkg; do
		yum --installroot=${VZ_CHROOT} --disablerepo=* --enablerepo=cab install -y $_pkg
	done < ${PACKAGES_LIST_FILE}
	yum --installroot=${VZ_CHROOT} clean all
}

_build_ct(){
	mkdir -p ${VZ_PKG_DIR} ${VZ_CHROOT}
	#without it, the initscript installation script will fail
	touch ${VZ_CHROOT}/random-seed
	case "${DISTRIB}" in 
		RedHat|redhat)
			PACKAGE_RELEASE_DISTRIB="redhat-release-server"
			yumdownloader --disablerepo=* --enablerepo=cab --destdir=${VZ_PKG_DIR} ${PACKAGE_RELEASE_DISTRIB}
		;;
		CentOS|centos)
			yumdownloader --disablerepo=* --enablerepo=cab --destdir=${VZ_PKG_DIR} ${PACKAGE_RELEASE_DISTRIB}
		;;
		*) _print "Sorry, ${DISTRIB} not supported. Only CentOS or RedHat" && exit 1
		;;
	esac
	rpm --rebuilddb --root=${VZ_CHROOT} 
	rpm -i --root=${VZ_CHROOT} --nodeps ${VZ_PKG_DIR}/*.rpm
	cp ${YUM_REPO_FILE} ${VZ_CHROOT}/etc/yum.repos.d/
	look_over_pkg_list
	yum --installroot=${VZ_CHROOT} clean all
}

post_conf_ct(){
	# Disk partitions are not needed in a container
	_print "\nnone /dev/pts devpts rw 0 0" > ${VZ_CHROOT}/etc/fstab
	# A container does not have real ttys
	sed -i -e 's/^[0-9].*getty.*tty/#&/g'  ${VZ_CHROOT}/etc/inittab
	# Change timezone
	[ -f /etc/localtime ] && cp -fp /etc/localtime ${VZ_CHROOT}/etc/localtime
	# Set non-interactive mode for initscripts (openvz bug #46)
	sed -i -e 's/^PROMPT=.*/PROMPT=no/' ${VZ_CHROOT}/etc/sysconfig/init
	sed -i 's|ACTIVE_CONSOLES=/dev/tty[1-6]|ACTIVE_CONSOLES=|g' ${VZ_CHROOT}/etc/sysconfig/init
	# Create /dev/pts
	mkdir -p ${VZ_CHROOT}/dev/pts
	# Create /etc/udev/devices
	mkdir -p ${VZ_CHROOT}/etc/udev/devices
	# Kill udevd
	sed -i 's|/sbin/start_udev|#/sbin/start_udev|g' $root/etc/rc.d/rc.sysinit
	# Create device nodes
	/sbin/MAKEDEV -d ${VZ_CHROOT}/dev -x console full null ptmx random urandom zero stdin stdout stderr
	/sbin/MAKEDEV -d ${VZ_CHROOT}/etc/udev/devices -x console full null ptmx random urandom zero stdin stdout stderr
	# Boot is not useful in a container since they run off the host kernel
	rm -rf ${VZ_CHROOT}/boot/*.*
	
}

make_tarball(){
	tar -czf ${OUTPUT_DIR}/${DISTRIB}-${DISTRIB_VERSION}_${ARCH}.tar.gz -C ${VZ_CHROOT} .
}

gen_repo_yum_conf(){
	_print "[cab]\nname=CentOS-mirror\nbaseurl=${MIRROR}\ngpgcheck=0\nenabled=0" > ${YUM_REPO_FILE}
}

clean(){
	rm -rf ${TPM} ${YUM_REPO_FILE} ${VZ_CHROOT}${YUM_REPO_FILE}
}


#MAIN
trap '{ echo "Hey, you pressed Ctrl-C. Time to quit." ; stty sane; exit 1; }' INT
case $1 in
	build)
		DISTRIB="$2"
		DISTRIB_VERSION="$3"
		ARCH="$4"
		PACKAGES_LIST_FILE="$5"
		MIRROR="$6"
		[ -z "${DISTRIB}" ] && { echo "Distrib is missing"; exit 1; }
		[ -z "${DISTRIB_VERSION}" ] && { echo "Distrib version is missing"; exit 1; }
		[ -z "${ARCH}" ] && { echo "Arch is missing"; exit 1; }
		[ -z "${PACKAGES_LIST_FILE}" ] && { echo "cab.pkglist is missing"; exit 1; }
		[ -z "${MIRROR}" ] && MIRROR=${MIRROR_DEFAULTS}
		gen_repo_yum_conf 
		_build_ct
		post_conf_ct
		make_tarball
		_print "Template can be found at: ${OUTPUT_DIR}/${DISTRIB}-${DISTRIB_VERSION}_${ARCH}.tar.gz"
		clean
	;;
        *)
		[ ! -z "$1" ] && _print "Unknown args '$1'"
		usage
	;;
esac
