#!/bin/sh
set -e

while [ $# -gt 0 ]; do
  key=$1

  case $key in
    --skip_openssl)
      SKIP_OPENSSL=1
      shift
      ;;
    --cxxobf)
      CXXOBF=$2
      shift
      shift
      ;;
    *)
      VERSION=$1
      shift
      ;;
  esac
done

if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <CURL Version>"
    exit 1
fi

############
# DOWNLOAD #
############

ARCHIVE=curl.tar.gz
if [ ! -f "${ARCHIVE}" ]; then
    echo "Downloading curl ${VERSION}"
    curl -L "https://curl.se/download/curl-${VERSION}.tar.gz" > "${ARCHIVE}"
fi

###########
# COMPILE #
###########

export OUTDIR=output
export BUILDDIR=build
export IPHONEOS_DEPLOYMENT_TARGET="9.3"

ROOTDIR="${PWD}"

function build() {
    ARCH=$1
    HOST=$2
    SDKDIR=$3
    LOG="../${ARCH}_build.log"
    echo "Building libcurl for ${ARCH}..."

    WORKDIR=curl_${ARCH}
    mkdir "${WORKDIR}"
    tar -xzf "${ROOTDIR}/${ARCHIVE}" -C "${WORKDIR}" --strip-components 1
    cd "${WORKDIR}"

    for FILE in $(find ../../patches -name '*.patch'); do
        patch -p1 < ${FILE}
    done

    unset CFLAGS
    unset LDFLAGS
    CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKDIR} -I${SDKDIR}/usr/include -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} -DHAVE_OPENSSL_ENGINE_H=1 -DUSE_OPENSSL_ENGINE"
    LDFLAGS="-arch ${ARCH} -isysroot ${SDKDIR}"
    export CFLAGS
    export LDFLAGS
    autoreconf -fi >> "${LOG}" 2>&1
    ./configure --host="${HOST}-apple-darwin" \
       --disable-shared \
       --enable-static \
       --disable-smtp \
       --disable-pop3 \
       --disable-imap \
       --disable-ftp \
       --disable-tftp \
       --disable-telnet \
       --disable-rtsp \
       --disable-ldap \
       --with-openssl=${ROOTDIR}/${OUTDIR}/${ARCH}/openssl \
       --without-zlib \
       --without-librtmp \
       --without-libidn \
       --disable-hidden-symbols \
       --disable-versioned-symbols \
       --without-brotli \
       --without-libidn2 \
       --without-nghttp2 \
       --without-libpsl >> "${LOG}" 2>&1
    # cp -r $ROOTDIR/user-exceptions.txt ./user-exceptions.txt

    # cp -r $ROOTDIR/build-script.pl ./build-script.pl
    mkdir -p ${ROOTDIR}/${BUILDDIR}/isolated_${WORKDIR}
    find . -type f -name "*.h" -or -name "*.c" >> files.list
    ${CXXOBF}/bin/cxx-obfus -x $ROOTDIR/user-exceptions.txt -x cpp -x iso -x motif -x posix2 -x stl -x unix95 -x x5 -x xpg4 -N none -n none -s none -i prefix,str=ISOLATED -S multifile,outdir=${ROOTDIR}/${BUILDDIR}/isolated_${WORKDIR},indir=${ROOTDIR}/${BUILDDIR}/${WORKDIR},filelist=./files.list
    # perl ./build-script.pl --op rebuildall --override-input-directory .

    # cp -rf ${ROOTDIR}/${BUILDDIR}/isolated_${WORKDIR}/* ${ROOTDIR}/${BUILDDIR}/${WORKDIR}/
    # make -j`sysctl -n hw.logicalcpu_max` >> "${LOG}" 2>&1

    mkdir -p ../../$OUTDIR/${ARCH}/curl/
    cp lib/.libs/libcurl.a ../../$OUTDIR/${ARCH}/curl/libcurl.a
    cd ../
}

# rm -rf $OUTDIR 
rm -rf $BUILDDIR
mkdir -p $OUTDIR
mkdir $BUILDDIR

# ###########
# # OPENSSL #
# ###########
# if ! [ -z $SKIP_OPENSSL ]; then
#     rm -f openssl-build-ios.sh
#     curl "https://raw.githubusercontent.com/kartaris/openssl-ios/master/build-ios.sh" > openssl-build-ios.sh
#     bash openssl-build-ios.sh 1.1.1d
# fi

mkdir -p $BUILDDIR
cd $BUILDDIR

build armv7    armv7   $(xcrun --sdk iphoneos --show-sdk-path)
build arm64    arm64   $(xcrun --sdk iphoneos --show-sdk-path)
build x86_64   x86_64  $(xcrun --sdk iphonesimulator --show-sdk-path)

cd ../

rm ${ARCHIVE}

mkdir -p $OUTDIR/armv7/curl/
mkdir -p $OUTDIR/arm64/curl/
mkdir -p $OUTDIR/x86_64/curl/
mkdir -p $OUTDIR/combined/curl/

lipo \
   -arch x86_64 $OUTDIR/x86_64/curl/libcurl.a \
   -arch armv7 $OUTDIR/armv7/curl/libcurl.a \
   -arch arm64 $OUTDIR/arm64/curl/libcurl.a \
   -create -output $OUTDIR/combined/curl/libcurl.a

###########
# PACKAGE #
###########

FWNAME=curl

if [ -d $FWNAME.framework ]; then
    echo "Removing previous $FWNAME.framework copy"
    rm -rf $FWNAME.framework
fi

LIBTOOL_FLAGS="-static"

echo "Creating $FWNAME.framework"
mkdir -p $FWNAME.framework/Headers/openssl
libtool -no_warning_for_no_symbols $LIBTOOL_FLAGS -o $FWNAME.framework/$FWNAME $OUTDIR/combined/curl/libcurl.a 
cp -r $BUILDDIR/curl_x86_64/include/$FWNAME/*.h $FWNAME.framework/Headers/

rm -rf $BUILDDIR
# rm -rf $OUTDIR

cp "Info.plist" $FWNAME.framework/Info.plist

set +e
check_bitcode=$(otool -arch arm64 -l $FWNAME.framework/$FWNAME | grep __bitcode)
if [ -z "$check_bitcode" ]
then
    echo "INFO: $FWNAME.framework doesn't contain Bitcode"
else
    echo "INFO: $FWNAME.framework contains Bitcode"
fi
