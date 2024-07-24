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
me=$dir/$prg
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
findar() {
	findf $1.tar.bz2 || findf $1.tar.gz || findf $1.tar.xz || findf $1.zip
}


##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes
    cmd_versions
    unset opts

	eset RASPBERRYPI_WORKSPACE=/tmp/tmp/$USER/RPi KERNELDIR=$HOME/tmp/linux
	WS=$RASPBERRYPI_WORKSPACE
	eset __kver=linux-rpi
	eset __kcfg=$dir/config/$__kver-reduced
	eset __kobj=$WS/obj/$(basename $__kcfg)
	eset \
		__kdir=$KERNELDIR/$__kver \
		__kbin=$__kobj/arch/arm64/boot/Image \
		__id=ddfb4433 \
		__tftproot=$WS/tftproot \
		__httproot=$WS/httproot \
		__bbcfg=$dir/config/$ver_busybox \
		__initrd=$__kobj/initrd.cpio.gz \
		__local_addr=192.168.40.1/24 \
		musldir=$GOPATH/src/github.com/richfelker/musl-cross-make

	if test "$cmd" = "env"; then
		set | grep -E "^($opts)="
		exit 0
	fi
	test -n "$long_opts" && export $long_opts

	mkdir -p $WS || die "Can't mkdir [$WS]"
	test -x $musldir/aarch64/bin/aarch64-linux-musl-gcc || \
		die "aarch64-linux-musl-gcc not found"
	export PATH=$musldir/aarch64/bin:$PATH
}
# Set variables unless already defined. Vars are collected into $opts
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
	done
}
##   versions [--brief]
##     Print used sw versions
cmd_versions() {
	test "$versions_shown" = "yes" && return 0
	versions_shown=yes
	unset opts
	eset \
		ver_busybox=busybox-1.36.1 \
		ver_atftp=atftp-0.8.0

	test "$cmd" != "versions" && return 0
	set | grep -E "^($opts)="
	test "$__brief" = "yes" && return 0

	echo "Downloaded:"
	local k v
	for k in $(echo $opts | tr '|' ' '); do
		v=$(eval echo \$$k)
		if findar $v; then
			echo $f
		else
			echo "Missing archive [$v]"
		fi
	done
	for v in bcm2711-rpi-4-b.dtb fixup4.dat start4.elf; do
		if findf $v; then
			echo $f
		else
			echo "Missing RPi file [$v]"
		fi
	done
}
# cdsrc <version>
# Cd to the source directory. Unpack the archive if necessary.
cdsrc() {
	test -n "$1" || die "cdsrc: no version"
	test "$__clean" = "yes" && rm -rf $WS/$1
	if ! test -d $WS/$1; then
		findar $1 || die "No archive for [$1]"
		if echo $f | grep -qF '.zip'; then
			unzip -d $WS -qq $f || die "Unzip [$f]"
		else
			tar -C $WS -xf $f || die "Unpack [$f]"
		fi
	fi
	cd $WS/$1
}
##   setup --dev=<your-UNUSED-wired-interface>
##     Setup from scratch. The kernel and BusyBox are built, and an
##     initrd created. The local interface, dhcpd and tftpd are setup.
##     RPi start files are copied to tftproot.  After this, the RPi
##     should be ready to boot.
##     WARNING: Requires "sudo"
cmd_setup() {
	cd $dir
	$me interface_setup || die interface_setup
	$me atftp_build || die atftp_build
	$me tftpd || die tftpd
	$me dhcpd || die dhcpd
	$me httpd || die httpd
	$me kernel_build || die kernel_build
	$me busybox_build || die busybox_build
	$me build_initrd ovl/initrd || die build_initrd
	$me tftp_setup || die tftp_setup
	$me collect_ovls ovl/rootfs
}
##   interface_setup --dev=<your-UNUSED-wired-interface>
##     Setup the local wired interface. An IPv4 /24 address must be used.
##     Iptables masquerading setup, and forward accepted.
##     WARNING: this requires "sudo" and may disable your network
##              if --dev is used for something
cmd_interface_setup() {
	test -n "$__dev" || die "No unused wired interface specified"
	if ip -4 addr show dev $__dev | grep -q inet; then
		log "IPv4 address already exist on [$__dev]"
		return 0
	fi
	ip link show $__dev > /dev/null || die "Not found [$__dev]"
	echo $__local_addr | grep -q '/24$' || \
		die "Not a IPv4 /24 address [$__local_addr]"
	sudo ip link set up $__dev || die "ip link set up"
	echo sudo ip addr add $__local_addr dev $__dev
	sudo ip addr add $__local_addr dev $__dev || die "addr add"
	local cidr=$(echo $__local_addr | sed -E 's,[0-9]+/24,0/24,')
	sudo iptables -t nat -A POSTROUTING -s $cidr -j MASQUERADE
	sudo iptables -A FORWARD -s $cidr -j ACCEPT
	sudo iptables -A FORWARD -d $cidr -j ACCEPT
}
##   kernel_build --tinyconfig  # Init the kcfg
##   kernel_build [--kver=] [--kcfg=] [--kdir=] [--kobj=] [--menuconfig]
##     Build the kernel
cmd_kernel_build() {
	test "$__clean" = "yes" && rm -rf $__kobj
	mkdir -p $__kobj
	local CCprefix=aarch64-linux-gnu-
	test "$__musl" = "yes" && CCprefix=aarch64-linux-musl-
	local make="make -C $__kdir O=$__kobj ARCH=arm64 CROSS_COMPILE=$CCprefix"
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
	cdsrc $ver_busybox
	if test "$__menuconfig" = "yes"; then
		test -r $__bbcfg && cp $__bbcfg ./.config
		make menuconfig
		cp ./.config $__bbcfg
	else
		test -r $__bbcfg || die "No config"
		cp $__bbcfg ./.config
	fi
	make -j$(nproc)
}
##   build_initrd [--initrd=] [ovls...]
##     Build a ramdisk (cpio archive) with busybox and the passed
##     ovls (a'la xcluster)
cmd_build_initrd() {
	local bb=$WS/$ver_busybox/busybox
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
		cmd_unpack_ovls $tmp/root $@
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
#   unpack_ovls <dst> [ovls...]
#     Unpack ovls to the <dst> dir
cmd_unpack_ovls() {
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
##   collect_ovls [ovls...]
##     Collect ovl's to the --httproot
cmd_collect_ovls() {
	mkdir -p $__httproot || dir "mkdir -p $__httproot"
	local out=$__httproot/ovls.txt
	rm $(find $__httproot -name '*.tar') $out 2> /dev/null
	local ovl i=1 f
	for ovl in $@; do
		f=$(printf "%02d%s.tar" $i $(basename $ovl))
		echo $f >> $out
		i=$((i + 1))
		test -x $ovl/tar || die "Not executable [$ovl/tar]"
		$ovl/tar $__httproot/$f || die "Failed [$ovl]"
	done
}
##   httpd
##     Start a http server on --local-addr and port 9090
cmd_httpd() {
	local adr=$(echo $__local_addr | cut -d/ -f1)
	mkdir -p $__httproot || dir "mkdir -p $__httproot"
	busybox httpd -p $adr:9090 -h $__httproot
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
##   atftp_build
##     Build atftp
cmd_atftp_build() {
	cdsrc $ver_atftp
	test -x "./atftpd" && return 0
	./autogen.sh || die autogen
	./configure || die configure
	make -j$(nproc) || die make
}
##   tftpd [--tftproot=$RASPBERRYPI_WORKSPACE/tftproot]
##     Start a tftpd server. Prerequisite: "atftp" is built
cmd_tftpd() {
	if pidof atftpd > /dev/null; then
		local pid=$(pidof atftpd)
		log "Tftpd (atftpd) already started as pid $pid"
		return 0
	fi
	local d=$WS/$ver_atftp
	test -x $d/atftpd || die "Not executable [$d/atftpd]"
	mkdir -p "$__tftproot"
	local adr=$(echo $__local_addr | cut -d/ -f1)
	sudo $d/atftpd --daemon --bind-address $adr $__tftproot
	log "Logs to syslog, tftproot=$__tftproot"
}
##   tftp_setup [--keep] [cfgdir]
##     Copy files from to cfgdir the tftp-boot directory. If cfgdir
##     is unspecified, a local kernel/initrd is assumed.
##     The tftp-boot directory is cleared, unless --keep is specified!
cmd_tftp_setup() {
	mkdir -p $__tftproot/$__id
	test "$__keep" = "yes" || rm $__tftproot/$__id/* > /dev/null 2>&1

	# Rpi firmware files
	local c
	for c in start4.elf fixup4.dat bcm2711-rpi-4-b.dtb; do
		findf $c || die "Not found [$c]"
		cp $f $__tftproot/$__id
	done

	if test -z "$1"; then
		log "Tftp setup with local kernel/initrd"
		test -r $__kbin || die "Not readable [$__kbin]"
		gzip -c $__kbin > $__tftproot/$__id/Image.gz
		test -r $__initrd || die "Not readable [$__initrd]"
		cp $__initrd $__tftproot/$__id
		cp $dir/config/cmdline.txt $dir/config/config.txt $__tftproot/$__id
	else
		c=$1
		test -d $c || die "Not a directory [$c]"
		test -r "$c/config.txt" || die "Not readable [$c/config.txt]"
		cp -r $c/* $__tftproot/$__id
	fi
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
	long_opts="$long_opts $o"
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
