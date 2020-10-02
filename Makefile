.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS = -ec

ROOT_DIR := $(PWD)
export PREFIX=$(ROOT_DIR)/install/
export CFLAGS=-I$(PREFIX)/include -O3 -flto --profiling
export CXXFLAGS=$(CFLAGS) -fno-rtti -fno-exceptions
export LDFLAGS=-L$(PREFIX)/lib -flto


.PHONY: serve default
default: serve

sources/emsdk.tar.gz:
	aria2c --check-integrity=true --auto-file-renaming=false \
	    https://github.com/emscripten-core/emsdk/archive/2.0.4.tar.gz \
	    --out=sources/emsdk.tar.gz \
	    --checksum=sha-256=55e2b4bd5a45fa5cba21eac4deaebda061edd4a2b8f753ffbce3f51eb19512da
sources/gmp.tar.xz:
	aria2c --check-integrity=true --auto-file-renaming=false \
	    https://gmplib.org/download/gmp/gmp-6.2.0.tar.xz \
	    --out=sources/gmp.tar.xz \
	    --checksum=sha-256=258e6cd51b3fbdfc185c716d55f82c08aff57df0c6fbd143cf6ed561267a1526
sources/mpfr.tar.xz:
	aria2c --check-integrity=true --auto-file-renaming=false \
	    https://www.mpfr.org/mpfr-current/mpfr-4.1.0.tar.xz \
	    --out=sources/mpfr.tar.xz \
	    --checksum=sha-256=0c98a3f1732ff6ca4ea690552079da9c597872d30e96ec28414ee23c95558a7f
sources/libxml2.tar.gz:
	aria2c --check-integrity=true --auto-file-renaming=false \
	    ftp://xmlsoft.org/libxml2/libxml2-2.9.10.tar.gz \
	    --out=sources/libxml2.tar.gz \
	    --checksum=sha-256=aafee193ffb8fe0c82d4afef6ef91972cbaf5feea100edc2f262750611b4be1f

sources/emsdk: sources/emsdk.tar.gz
	pushd sources
	tar xf emsdk.tar.gz
	mv emsdk-* emsdk
	popd
sources/gmp: sources/gmp.tar.xz
	pushd sources
	tar xf gmp.tar.xz
	mv gmp-* gmp
	popd
sources/libqalculate:
	pushd sources
	git clone git@github.com:Qalculate/libqalculate.git
	cd libqalculate
	git reset --hard 57e1593e9074d6f491d60a8afa4013375e199b9f
	popd
sources/mpfr: sources/mpfr.tar.xz
	pushd sources
	tar xf mpfr.tar.xz
	mv mpfr-* mpfr
	popd
sources/libxml2: sources/libxml2.tar.gz
	pushd sources
	tar xf libxml2.tar.gz
	mv libxml2-* libxml2
	popd

sources/emsdk/upstream/.emsdk_version: sources/emsdk
	pushd sources/emsdk
	./emsdk install 2.0.4
	./emsdk activate 2.0.4
	popd

install/lib/libxml2.a: sources/emsdk/upstream/.emsdk_version sources/libxml2/*.c
	. sources/emsdk/emsdk_env.sh
	pushd sources/libxml2
	emconfigure ./configure --host none --prefix="${PREFIX}" \
	    --with-minimum --with-sax1 --with-tree --with-output
	make PROGRAMS= -j "$(shell nproc)" install
	popd

install/lib/libgmp.a: sources/emsdk/upstream/.emsdk_version sources/gmp/*.c
	. sources/emsdk/emsdk_env.sh
	pushd sources/gmp
	emconfigure ./configure --host none --prefix="${PREFIX}" \
		--disable-assembly --disable-cxx --disable-fft \
		--enable-alloca=notreentrant
	make -j "$(shell nproc)" install
	popd

install/lib/libmpfr.a: sources/emsdk/upstream/.emsdk_version sources/mpfr/src/*.c install/lib/libgmp.a
	. sources/emsdk/emsdk_env.sh
	pushd sources/mpfr
	emconfigure ./configure --host none --prefix="${PREFIX}" \
		--disable-thread-safe --enable-decimal-float=no
	make -j "$(shell nproc)" install
	popd

install/lib/libqalculate.a: sources/emsdk/upstream/.emsdk_version sources/libqalculate install/lib/libgmp.a install/lib/libmpfr.a install/lib/libxml2.a
	. sources/emsdk/emsdk_env.sh
	pushd sources/libqalculate
	OUT="$$(patch -p1 --forward < $(ROOT_DIR)/libqalculate-popen.patch)" || echo "$${OUT}" | grep "Skipping patch" -q || (echo "$OUT" && false);
	NOCONFIGURE=true ./autogen.sh
	LIBXML_CFLAGS="-I${PREFIX}/include/libxml2" LIBXML_LIBS="${LDFLAGS}" emconfigure ./configure --host none --prefix="${PREFIX}" \
		--without-libcurl --without-icu --disable-textport --disable-nls \
		--enable-compiled-definitions
	make -j "$(shell nproc)" install
	popd

build/qalc.js: sources/emsdk/upstream/.emsdk_version install/lib/libqalculate.a
	. sources/emsdk/emsdk_env.sh
	mkdir -p build
	export EMMAKEN_CFLAGS="$(CFLAGS) $(CXXFLAGS) $(LDFLAGS)"
	emcc \
	    --source-map-base http://localhost:8000/build/ \
	    -s DEMANGLE_SUPPORT=1 -s WARN_UNALIGNED=1 -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
	    -s EXPORTED_FUNCTIONS='["_calculate", "_free", "_newCalculator"]' \
	    -s EXTRA_EXPORTED_RUNTIME_METHODS='["cwrap"]' \
	    -llibqalculate -lgmp -lmpfr -lxml2 \
	    $(ROOT_DIR)/test.cpp \
	    -o build/qalc.js


serve: build/qalc.js
	python3 -m http.server 8000
