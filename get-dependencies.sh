#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# gopher64 vendors SDL3 and the Vulkan headers, so a compiler, cmake and ninja
# are enough to build them. clang is what upstream builds the C with.
pacman -Syu --noconfirm \
	base-devel \
	clang      \
	cmake      \
	git        \
	ninja      \
	patchelf   \
	rustup

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common

REPO=https://github.com/gopher64/gopher64
git clone "$REPO" ./gopher64 && (
	cd ./gopher64
	if [ "${DEVEL_RELEASE-}" = 1 ]; then
		echo "Making nightly build of gopher64..."
		echo "---------------------------------------------------------------"
		VERSION="$(git rev-parse --short HEAD)"
	else
		echo "Making stable build of gopher64..."
		echo "---------------------------------------------------------------"
		git fetch --tags origin
		VERSION=$(git tag --sort=-v:refname | grep -vi 'rc\|alpha\|beta\|nightly' | head -1)
		git checkout "$VERSION"
	fi
	echo "$VERSION" > ~/version
	git submodule update --init --recursive --depth 1

	# gopher64 builds for x86-64-v3 and Cortex-A76 only, and its RSP cores call
	# SSE4.1 intrinsics that older x86-64 CPUs do not have. The patch lowers the
	# target to Core 2 Duo and to the aarch64 baseline, keeps the SSE4.1 fast
	# path for CPUs that have it, and adds plain C versions of the intrinsics
	# riscv64, loongarch64 and ppc64 are missing.
	git apply -p1 ../patches/generic-simd.patch

	# build with the rust version gopher64 pins in rust-toolchain.toml
	rustup toolchain install "$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)" \
		--profile minimal
	cargo build --release --locked
	mkdir -p ../AppDir/bin
	mv -v ./target/release/gopher64 ../AppDir/bin
)
