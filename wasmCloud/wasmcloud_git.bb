inherit cargo_bin
SUMMARY = "wasmCloud host runtime"
HOMEPAGE = "https://github.com/wasmCloud/wasmCloud"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=398c810c4f475ff8ab49ba8d2ba614c1"
SRC_URI = "git://github.com/wasmCloud/wasmCloud.git;protocol=https;branch=release/v0.82.0"
PV = "1.0+git${SRCPV}"
SRCREV = "9efb52976b4224aaece5fd430cd7e45ff4aa567c"
S = "${WORKDIR}/git"
# Enable network for the compile task allowing cargo to download dependencies
do_compile[network] = "1"
