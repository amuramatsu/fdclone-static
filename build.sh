#! /bin/sh
#
# build script with dockcross
#

fdclone_version="3.01j"
fdclone_sha1="f223051eef1070d4ad84d8545fc05e294719a7de"
netbsd_curses_version="0.3.2"
netbsd_curses_sha1="ffffe30ed60ef619e727260ec4994f7bf819728e"
musl_version="1.2.5"
musl_sha1="36210d3423172a40ddcf83c762207c5f760b60a6"
musl_patch1="https://www.openwall.com/lists/musl/2025/02/13/1/1"
musl_patch1_sha1="83b881fbe8a5d4d340977723adda4f8ac66592f0"
musl_patch2="https://www.openwall.com/lists/musl/2025/02/13/1/2"
musl_patch2_sha1="0ceaa0467429057efce879b6346efa4f58c7cd4d"

release_dir="fdclone-static-${fdclone_version}_musl-${musl_version}-${netbsd_curses_version}"

if [ -z "$1" ]; then
    echo "Usage: $0 ARCH"
    echo ""
    echo "   supported ARCHes are"
    echo "     arm64, armhf, armel, i486, amd64, mips, mipsel,"
    echo "     powerpc, ppc64el, s390x"
    echo ""
    exit 1
fi

CFLAGS=
LDFLAGS=
musl_configure=
fdclone_makeargs=
fdclone_patch="$(pwd)/fdclone-${fdclone_version}.patch"
curses_configure=
curses_patch="$(pwd)/netbsd-curses-${netbsd_curses_version}.patch"
strip=
arch="$1"
link_hack=
case $arch in
    arm64)
	dockcross_arch=linux-arm64
	;;
    armhf)
	dockcross_arch=linux-armv7
	CFLAGS="-mfloat-abi=hard"
	;;
    armel)
	dockcross_arch=linux-armv5
    	CFLAGS="-mfloat-abi=soft"
    	;;
    i486)
	#dockcross_arch=linux-x86
	dockcross_arch=linux-i686
	musl_configure="--target i386-linux-gnu RANLIB=ranlib"
	CFLAGS="-march=i486 -m32"
	LDFLAGS="-m32"
	link_hack=-melf_i386
	strip=strip
	;;
    amd64)
	dockcross_arch=linux-x64
	;;
    mips) 
	dockcross_arch=linux-mips
	;;
    mipsel)
	dockcross_arch=linux-mipsel-lts
	;;
    powerpc)
	dockcross_arch=linux-ppc
	CFLAGS="-mbig -mlong-double-64"
	;;
    ppc64el)
	dockcross_arch=linux-ppc64le
	CFLAGS="-mlong-double-64"
	;;
    riscv32)
	dockcross_arch=linux-riscv32
	;;
    riscv64)
	dockcross_arch=linux-riscv64
	;;
    s390x)
	dockcross_arch=linux-s390x
	;;
    *)
	echo "unknown archtecture $arch"
	exit 1
	;;
esac

build_dir="$(pwd)/build"
archives_dir="$(pwd)/archives"

sha1_digest() {
    FILE="$1"
    shasum=
    for bindir in /usr/bin /usr/local/bin /usr/pkg/bin /opt/local/bin; do
	if [ -x "${bindir}/shasum" ]; then
	    shasum="${bindir}/shasum"
	    break
	fi
    done
    if [ x"$shasum" = x"" ]; then
	shasum='openssl dgst -sha1 -r'
    fi
    $shasum "$FILE" | awk '{print $1}'
}

download() {
    URL="$1"
    SHA="$2"
    filename="$3"
    [ -d "$archives_dir" ] || mkdir -p "$archives_dir"
    if [ x"$filename" = x"" ]; then
	filename="$(basename "$URL")"
    fi
    if [ -r "${archives_dir}/${filename}" ]; then
	digest=$(sha1_digest "${archives_dir}/${filename}")
	if [ x"$digest" = x"$SHA" ]; then
	    return
	fi
	rm -f "${archives_dir}/${filename}"
    fi
    curl -L -o "${archives_dir}/${filename}" "${URL}"
}

if [ -d "$build_dir" ]; then
  echo "= removing previous build directory"
  rm -rf "$build_dir"
fi

mkdir -p "$build_dir"
curdir="$(pwd)"
cd "$build_dir"
working_dir="$(pwd)"

docker run --rm "dockcross/${dockcross_arch}" > ./dockcross
chmod +x dockcross
./dockcross update # update dockcross environment!
dockerwork_dir=$(./dockcross bash -c 'echo -n $(pwd)')

# download tarballs
echo "= downloading fdclone"
download "http://www.unixusers.net/authors/VA012337/soft/fd/FD-${fdclone_version}.tar.gz" $fdclone_sha1 "FD-${fdclone_version}.tar.gz"

echo "= extracting fdclone"
gzip -cd "${archives_dir}/FD-${fdclone_version}.tar.gz" | tar xf - 

echo "= downloading musl"
download "http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz" $musl_sha1
download $musl_patch1 $musl_patch1_sha1 musl.patch1
download $musl_patch2 $musl_patch2_sha1 musl.patch2

echo "= extracting musl"
musl_dir="musl-${musl_version}"
gzip -cd "${archives_dir}/musl-${musl_version}.tar.gz" | tar xf -
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch1")
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch2")

echo "= downloading netbsd-curses"
download "http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-${netbsd_curses_version}.tar.xz" $netbsd_curses_sha1

echo "= extracting netbsd-curses"
xz -cd "${archives_dir}/netbsd-curses-${netbsd_curses_version}.tar.xz" | tar xf -

echo "= building musl"

install_dir="${dockerwork_dir}/musl-install"

./dockcross bash -c "cd ${musl_dir} && ./configure '--prefix=${install_dir}' --disable-shared ${musl_configure} 'CFLAGS=$CFLAGS'"
./dockcross bash -c "cd ${musl_dir} && make install"

echo "= setting CC to musl-gcc"
CC="${dockerwork_dir}/musl-install/bin/musl-gcc"
if [ ! -z "$link_hack" ]; then
    echo "= hack for link with musl-gcc"
    sed -i.bak "s/-dynamic-linker/$link_hack -dynamic-linker/" "${working_dir}/musl-install/lib/musl-gcc.specs"
fi

echo "= building netbsd-curses"

curses_dir="netbsd-curses-${netbsd_curses_version}"
(cd "$curses_dir" && patch -p1 < "$curses_patch")
./dockcross bash -c "cd '${curses_dir}' && make 'CC=$CC' 'HOSTCC=gcc' 'CFLAGS=-Os -std=gnu11 $CFLAGS' 'LDFLAGS=-static $LDFLAGS' 'PREFIX=${install_dir}' all-static install-static"

echo "= building fdclone"

fdclone_dir="FD-${fdclone_version}"
(cd "$fdclone_dir" && patch -p1 < "$fdclone_patch")
echo "#define _NODOSDRIVE"  >> "${fdclone_dir}/config.hin"
echo "#define _NOROCKRIDGE" >> "${fdclone_dir}/config.hin"
echo "#define _NOWRITEFS"   >> "${fdclone_dir}/config.hin"
echo "#define _NOJPNMES"    >> "${fdclone_dir}/config.hin"
echo "#define _NOCATALOG"   >> "${fdclone_dir}/config.hin"
echo "#define _NOUNICDTBL"  >> "${fdclone_dir}/config.hin"
./dockcross bash -c "cd '${fdclone_dir}' && make 'CC=$CC' 'CFLAGS=-static $CFLAGS' 'LDFLAGS=-static $LDFLAGS' HOSTCC=gcc HOSTCFLAGS= HOSTLDFLAGS= ${fdclone_makeargs}"

cd "${curdir}"

[ -d "${release_dir}" ] || mkdir -p "${release_dir}"

echo "= copy fdclone binary"
cp "${build_dir}/${fdclone_dir}/FAQ"          "${release_dir}"
cp "${build_dir}/${fdclone_dir}/FAQ.eng"      "${release_dir}"
cp "${build_dir}/${fdclone_dir}/LICENSES"     "${release_dir}"
cp "${build_dir}/${fdclone_dir}/LICENSES.eng" "${release_dir}"
cp "${build_dir}/${fdclone_dir}/fd-dict.tbl"  "${release_dir}"
cp "${build_dir}/${fdclone_dir}/_fdrc"        "${release_dir}/_fd2rc"
cp "${build_dir}/${fdclone_dir}/fd.cat"       "${release_dir}/fd.jman"
cp "${build_dir}/${fdclone_dir}/fd_e.cat"     "${release_dir}/fd.man"
cp "${build_dir}/${fdclone_dir}/fd.man"       "${release_dir}/fd.1j"
cp "${build_dir}/${fdclone_dir}/fd_e.man"     "${release_dir}/fd.1"
cp "${build_dir}/${fdclone_dir}/fd"           "${release_dir}/fd-${arch}"
if [ x"$strip" = x"" ]; then
    "${build_dir}/dockcross" bash -c 'STRIP=$(echo $CC|sed s/-gcc\$/-strip/); $STRIP -s '"'${release_dir}/fd-${arch}'"
else
    "${build_dir}/dockcross" bash -c "$strip -s '${release_dir}/fd-${arch}'"
fi

# remove ACL at macOS
uname_s=$(uname -s)
if [ x"$uname_s" = x"Darwin" ]; then
    for a in com.docker.owner com.docker.grpcfuse.ownership; do
        xattr -d "$a" "${release_dir}/fd-${arch}" >/dev/null 2>&1
    done
fi

echo "= done"
