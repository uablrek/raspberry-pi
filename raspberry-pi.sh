#! /bin/sh
##
## raspberry-pi.sh --
##
##   Script for managing raspberry-pi
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
tmp=/tmp/${prg}_$$

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$*" >&2
}
findf() {
	f=$HOME/Downloads/$1
	test -r $f && return 0
	test -n "$ARCHIVE" && f=$ARCHIVE/$1
	test -r $f
}
crossenv_setup() {
	musldir=$GOPATH/src/github.com/richfelker/musl-cross-make
	test -x $musldir/output/bin/aarch64-linux-musl-gcc || \
		die "musl-cross-make not installed"
	export PATH=$musldir/output/bin:$PATH
}


##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes

	test -n "$RASPBERRYPI_WORKSPACE" || RASPBERRYPI_WORKSPACE=$HOME/tmp/raspberrypi
	WS=$RASPBERRYPI_WORKSPACE
	test -n "$__kver" || __kver=linux-rpi
	test -n "$__kdir" || __kdir=$WS/linux/$__kver
	test -n "$__kcfg" || __kcfg=$dir/config/$__kver-reduced
	test -n "$__kobj" || __kobj=$WS/obj/$(basename $__kcfg)
	test -n "$__kbin" || __kbin=$__kobj/arch/arm64/boot/Image
	test -n "$__id" || __id=ddfb4433
	test -n "$__tftproot" || __tftproot=$WS/tftproot
	test -n "$__bbver" || __bbver=busybox-1.36.1
	test -n "$__bbcfg" || __bbcfg=$dir/config/$__bbver
	test -n "$__initrd" || __initrd=$__kobj/initrd.cpio.gz
	test -n "$__local_addr" || __local_addr=192.168.40.1
	test -n "$__atftpdir" || __atftpdir=$WS/atftp
	if test "$cmd" = "env"; then
		opts="kver|kdir|kcfg|kobj|kbin|id|tftproot|bbver|bbcfg|initrd|local_addr|atftpdir"
		set | grep -E "^(__($opts)|ARCHIVE|RASPBERRYPI_.*)="
		exit 0
	fi
	mkdir -p $WS || die "Can't mkdir [$WS]"
}
##   kernel_build --tinyconfig  # Init the kcfg
##   kernel_build [--kver=] [--kcfg=] [--kdir=] [--kobj=] [--menuconfig]
##     Build the kernel
cmd_kernel_build() {
	mkdir -p $__kobj
	local make="make -C $__kdir O=$__kobj ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
	if test "$__tinyconfig" = "yes"; then
		rm -r $__kobj
		mkdir -p $__kobj $(dirname $__kcfg)
		$make -C $__kdir O=$__kobj tinyconfig
		cp $__kobj/.config $__kcfg
		__menuconfig=yes
	fi

	test -r $__kcfg || die "Not readable [$__kcfg]"
	cp $__kcfg $__kobj/.config
	if test "$__menuconfig" = "yes"; then
		$make menuconfig
		cp $__kobj/.config $__kcfg
	else
		$make oldconfig
	fi
	$make -j$(nproc) Image modules dtbs
}
##   busybox_build [--bbcfg=] [--menuconfig]
##     Build BusyBox for target aarch64-linux-musl-
cmd_busybox_build() {
	findf $__bbver.tar.bz2 || die "Can't find [$__bbver.tar.bz2]"
	local d=$WS/$__bbver
	if ! test -d $d; then
		tar -C $WS -xf $f || die
	fi
	crossenv_setup
	if test "$__menuconfig" = "yes"; then
		test -r $__bbcfg && cp $__bbcfg $d/.config
		make -C $d menuconfig
		cp $d/.config $__bbcfg
	else
		test -r $__bbcfg || die "No config"
		cp $__bbcfg $d/.config
		make oldconfig
	fi
	make -C $d -j$(nproc)
}
##   build_initrd [--initrd=] [ovls...]
##     Build a ramdisk (cpio archive) with busybox and the passed
##     ovls (a'la xcluster)
cmd_build_initrd() {
	local bb=$WS/$__bbver/busybox
	test -x $bb || die "Not executable [$bb]"
	touch $__initrd || die "Can't create [$__initrd]"

	cmd_gen_init_cpio
	gen_init_cpio=$WS/bin/gen_init_cpio
	mkdir -p $tmp
	cat > $tmp/cpio-list <<EOF
dir /dev 755 0 0
nod /dev/console 644 0 0 c 5 1
dir /bin 755 0 0
file /bin/busybox $bb 755 0 0
slink /bin/sh busybox 755 0 0
EOF
	if test -n "$1"; then
		cmd_collect_ovls $tmp/root $@
		cmd_emit_list $tmp/root >> $tmp/cpio-list
	else
		cat >> $tmp/cpio-list <<EOF
dir /etc 755 0 0
file /init $dir/config/init-tiny 755 0 0
EOF
	fi
	$gen_init_cpio $tmp/cpio-list | gzip -c > $__initrd
	#zcat $__initrd | cpio -i --list
}
#   gen_init_cpio
#     Build the kernel gen_init_cpio utility
cmd_gen_init_cpio() {
	local x=$WS/bin/gen_init_cpio
	test -x $x && return 0
	mkdir -p $(dirname $x)
	local src=$__kdir/usr/gen_init_cpio.c
	test -r $src || die "Not readable [$src]"
	gcc -o $x $src
}
#   collect_ovls <dst> [ovls...]
#     Collect ovls to the <dst> dir
cmd_collect_ovls() {
	test -n "$1" || die "No dest"
	test -e $1 -a ! -d "$1" && die "Not a directory [$1]"
	mkdir -p $1 || die "Failed mkdir [$1]"
	local ovl d=$1
	shift
	for ovl in $@; do
		test -x $ovl/tar || die "Not executable [$ovl/tar]"
		$ovl/tar - | tar -C $d -x || die "Unpack [$ovl]"
	done
}
#   emit_list <src>
#     Emit a gen_init_cpio list built from the passed <src> dir
cmd_emit_list() {
	test -n "$1" || die "No source"
	local x p d=$1
	test -d $d || die "Not a directory [$d]"
	cd $d
	for x in $(find . -mindepth 1 -type d | cut -c2-); do
		p=$(stat --printf='%a' $d$x)
		echo "dir $x $p 0 0"
	done
	for x in $(find . -mindepth 1 -type f | cut -c2-); do
		p=$(stat --printf='%a' $d$x)
		echo "file $x $d$x $p 0 0"
	done
}
##   dhcpd
##     Start "busybox udhcpd" as dhcp server
cmd_dhcpd() {
	which busybox > /dev/null || die "Not executable [busybox]"
	busybox udhcpd -h 2>&1 | grep -q Usage: || \
		die "busybox udhcpd applet not supported"
	if test -r /var/run/udhcpd.pid; then
		local pid=$(cat /var/run/udhcpd.pid)
		log "busybox udhcpd already running as pid $pid"
		return 0
	fi
	touch /tmp/udhcpd.leases
	sudo busybox udhcpd -S $dir/config/udhcpd.conf
}

##   tftpd [--tftproot=$RASPBERRYPI_WORKSPACE/tftproot]
##     Start a tftpd server. Prerequisite: "atftp" is built
cmd_tftpd() {
	if pidof atftpd > /dev/null; then
		local pid=$(pidof atftpd)
		log "Tftpd (atftpd) already started as pid $pid"
		return 0
	fi
	test -x $__atftpdir/atftpd || die "Not executable [$__atftpdir/atftpd]"
	mkdir -p "$__tftproot"
	sudo $__atftpdir/atftpd --daemon --bind-address $__local_addr $__tftproot
	log "Logs to syslog, tftproot=$__tftproot"
}
##   tftp_setup <alpine|local>
##     Copy appropriate files to the tftp-boot directory
cmd_tftp_setup() {
	test -n "$1" || die "No setup"
	# Configs
	local c n
	mkdir -p $__tftproot/$__id
	rm $__tftproot/$__id/* > /dev/null 2>&1
	for c in $1-cmdline.txt $1-config.txt; do
		test -r $dir/config/$c || die "Not readable [$dir/config/$c]"
		n=$(echo $c | sed -e "s,$1-,,")
		cp $dir/config/$c $__tftproot/$__id/$n
	done
	# Rpi files
	for c in start4.elf fixup4.dat bcm2711-rpi-4-b.dtb; do
		findf $c || die "Not found [$c]"
		cp $f $__tftproot/$__id
	done
	# Specific files
	case $1 in
		local)
			test -r $__kbin || die "Not readable [$__kbin]"
			gzip -c $__kbin > $__tftproot/$__id/Image.gz
			test -r $__initrd || die "Not readable [$__initrd]"
			cp $__initrd $__tftproot/$__id
			;;
		alpine)
			findf vmlinuz-rpi4 || die "Not found [vmlinuz-rpi4]"
			cp $f $__tftproot/$__id
			#gzip -c $__kbin > $__tftproot/$__id/vmlinuz-rpi4
			findf initramfs-rpi4 || die "Not found [initramfs-rpi4]"
			cp $f $__tftproot/$__id
			;;
	esac
}

##
# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
	if echo $1 | grep -q =; then
		o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
		v=$(echo "$1" | cut -d= -f2-)
		eval "$o=\"$v\""
	else
		if test "$1" = "--"; then
			shift
			break
		fi
		o=$(echo "$1" | sed -e 's,-,_,g')
		eval "$o=yes"
	fi
	shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
