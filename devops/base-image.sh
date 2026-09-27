#!/bin/sh
#
# Sourced by the build scripts once IMAGE and BASE_IMAGE are set; not meant to
# be run on its own.
#
# If CONTAINERFILE names a file, it is built on top of BASE_IMAGE (handed to it
# as the build arg of the same name) and the agent is installed on the result
# instead. `make images` sets it when ./Containerfile exists; CI runs the build
# scripts directly and never sets it, so its images come from the stock base.
#
# Keep this straight-line: the callers rely on set -e to stop at a failed
# build, which it won't if this is sourced from an if or beside || or &&.

if [ -n "${CONTAINERFILE:-}" ]; then
	[ -f "$CONTAINERFILE" ] || {
		echo "CONTAINERFILE: no such file: $CONTAINERFILE"
		exit 1
	}
	# --layers caches each step, so a new agent release only rebuilds the
	# agent's own layer. The cache expires after a week so a nightly
	# toolchain can't go stale forever; NO_CACHE=1 refreshes it now.
	buildah build \
		--layers \
		--cache-ttl=168h \
		${NO_CACHE:+--no-cache} \
		--build-arg "BASE_IMAGE=$BASE_IMAGE" \
		--file "$CONTAINERFILE" \
		--tag "localhost/${IMAGE}-base" \
		"$(dirname "$CONTAINERFILE")"
	BASE_IMAGE="localhost/${IMAGE}-base"
elif [ -z "${CONTAINERFILE+set}" ] && [ -f "$(dirname "$0")/../Containerfile" ]; then
	echo "Note: ./Containerfile is only layered in by 'make images' (or CONTAINERFILE=...)"
fi

echo "Building ${IMAGE} on ${BASE_IMAGE}${CONTAINERFILE:+ (from $CONTAINERFILE)}"
