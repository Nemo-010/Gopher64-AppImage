#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# gopher64 vendors SDL3 and the Vulkan headers, so a compiler, cmake and ninja
# are enough to build them. llvm supplies llvm-ar, which .cargo/config.toml sets
# as the archiver, and lld is the linker it asks for on aarch64. fontconfig is
# there for the fontconfig-sys crate, which looks for it with pkg-config.
#
# rust comes from the repositories rather than from rustup: rustup has no
# loongarch64 toolchain it can download from inside the build containers, and
# the ppc64 one it offers is ELFv1 while ArchPOWER is ELFv2. The repositories
# have a rust for every architecture gopher64 is built for.
pacman -Syu --noconfirm \
	base-devel \
	clang      \
	cmake      \
	fontconfig \
	git        \
	lld        \
	llvm       \
	ninja      \
	patchelf   \
	rust

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common

# gopher64 asks for rust 1.99.0, but the ArchPOWER port only has 1.97.1. That
# is new enough for what the code uses: the newest things in it are let chains
# and is_multiple_of, from 1.88 and 1.87.
case "$ARCH" in
	ppc64le | ppc64) CARGO_FLAGS="--ignore-rust-version";;
	*) CARGO_FLAGS="";;
esac

echo "Making stable build of gopher64..."
echo "---------------------------------------------------------------"
REPO=https://github.com/gopher64/gopher64
git clone "$REPO" ./gopher64 && (
	cd ./gopher64
	git fetch --tags origin
	TAG=$(git tag --sort=-v:refname | grep -vi 'rc\|alpha\|beta\|nightly' | head -1)
	git checkout "$TAG"
	echo "$TAG" > ~/version
	git submodule update --init --recursive --depth 1

	# gopher64 builds for x86-64-v3 and Cortex-A76 only, and its RSP cores call
	# SSE4.1 intrinsics that older x86-64 CPUs do not have. The patch lowers the
	# target to Core 2 Duo and to the aarch64 baseline, keeps the SSE4.1 fast
	# path for CPUs that have it, and adds plain C versions of the intrinsics
	# riscv64, loongarch64 and ppc64 are missing.
	git apply -p1 ../patches/generic-simd.patch

	# nix 0.26, pulled in by webrtc-util for netplay, predates loongarch64 and
	# does not compile there. Vendor it with the missing architecture added.
	if [ "$ARCH" = loongarch64 ]; then
		cargo fetch --locked
		cp -r "$(find /root/.cargo/registry/src -maxdepth 2 -type d -name 'nix-0.26.4' | head -1)" \
			../vendor-nix
		chmod -R u+w ../vendor-nix
		patch -d ../vendor-nix -p1 < ../patches/nix-loongarch64.patch
		printf '\n[patch.crates-io]\nnix = { path = "../vendor-nix" }\n' >> Cargo.toml
		# the patch section changes the lockfile, so it can no longer be used
		CARGO_FLAGS="$CARGO_FLAGS --offline"
	fi

	cargo build --release $CARGO_FLAGS
	mkdir -p ../AppDir/bin
	mv -v ./target/release/gopher64 ../AppDir/bin
)
