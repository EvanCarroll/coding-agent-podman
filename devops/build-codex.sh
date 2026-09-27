#!/bin/sh
#
# Build the OpenAI Codex image with buildah.
#
# Everything except the final image reference is written to stderr, so the
# only line on stdout is "codex:<version>" for callers (CI) to consume.
#
# BASE_IMAGE replaces the image it builds on, and CONTAINERFILE layers one of
# your own under it; see devops/base-image.sh.

set -eu

exec 3>&1
exec 1>&2

IMAGE=codex
# Resolved before anything is built, so a missing npm fails fast rather than
# after a long custom base build.
CODEX_VERSION=$(npm info @openai/codex --json | jq -er .version) || {
	echo "Could not resolve the @openai/codex version from npm"
	exit 1
}

BASE_IMAGE=${BASE_IMAGE:-docker.io/alpine:latest}
. "$(dirname "$0")/base-image.sh"
CONTAINER=$(buildah from "$BASE_IMAGE")

# The codex npm package is a thin JS shim around a native binary, so node is
# needed at runtime. That binary is statically musl-linked, so gcompat is not
# required; libstdc++ is pulled in as a nodejs dependency. zsh is required by
# the launcher's --apk-packages and --init-script flags. git is only needed
# while npm resolves the install, so it goes in as a virtual package and comes
# straight back out. It runs as root even if a custom base ends with a USER of
# its own.
buildah run --user 0:0 "$CONTAINER" sh <<-EOT
	set -eu
	apk update
	apk add --no-cache nodejs npm zsh
	apk add --no-cache --virtual .codex-build-deps git
	npm install --omit=dev --no-audit --no-fund -g @openai/codex
	apk del .codex-build-deps
	apk cache clean
	rm -rf /usr/lib/node_modules/npm/man/ /root/.npm
	adduser -D -u 1000 codex
	# CODEX_HOME must exist or codex warns on every start; the launcher
	# mounts the host's ~/.codex over the top of it.
	install -d -o codex -g codex /home/codex/.codex
EOT

# Resolve rather than hardcode, so an npm prefix change can't silently break
# the image. Alpine's npm ships prefix=/usr/local, so this is /usr/local/bin/codex.
CODEX_BIN=$(buildah run "$CONTAINER" sh -c 'command -v codex' | tr -d '\r\n')

# Keep the base's PATH, which a custom base may have extended, rather than
# hardcoding the stock one. No pipe here: without pipefail, a failed run
# would slip past set -e and ship an empty PATH.
BASE_PATH=$(buildah run "$CONTAINER" printenv PATH)

buildah config \
	--author "Evan Carroll" \
	--env "PATH=$BASE_PATH" \
	--env "SHELL=/bin/zsh" \
	--env "CODEX_HOME=/home/codex/.codex" \
	--cmd "" \
	--entrypoint "[ \"$CODEX_BIN\" ]" \
	--annotation "com.openai.codex.version=$CODEX_VERSION" \
	--annotation "org.opencontainers.image.title=codex" \
	--annotation "org.opencontainers.image.description=OpenAI Codex on Alpine ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/EvanCarroll/coding-agent-podman" \
	--annotation "org.opencontainers.image.source=https://github.com/EvanCarroll/coding-agent-podman" \
	--annotation "org.opencontainers.image.documentation=https://github.com/EvanCarroll/coding-agent-podman/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "${IMAGE}:${CODEX_VERSION}"

echo "Built ${IMAGE}:${CODEX_VERSION} (also tagged ${IMAGE}:latest)"
echo "To use this image run: codex-podman --local"

echo "${IMAGE}:${CODEX_VERSION}" >&3
