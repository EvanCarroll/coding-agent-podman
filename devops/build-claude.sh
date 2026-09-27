#!/bin/sh
#
# Build the Claude Code image with buildah.
#
# Everything except the final image reference is written to stderr, so the
# only line on stdout is "claude-code:<version>" for callers (CI) to consume.
#
# BASE_IMAGE replaces the image it builds on, and CONTAINERFILE layers one of
# your own under it; see devops/base-image.sh.

set -eu

exec 3>&1
exec 1>&2

IMAGE=claude-code
# Resolved before anything is built, so a missing npm fails fast rather than
# after a long custom base build.
CLAUDE_VERSION=$(npm info @anthropic-ai/claude-code --json | jq -er .version) || {
	echo "Could not resolve the @anthropic-ai/claude-code version from npm"
	exit 1
}

BASE_IMAGE=${BASE_IMAGE:-docker.io/node:current-alpine}
. "$(dirname "$0")/base-image.sh"
CONTAINER=$(buildah from "$BASE_IMAGE")

# As root even if a custom base ends with a USER of its own.
buildah run --user 0:0 "$CONTAINER" sh <<-EOT
	set -eu
	npm config set os linux
	apk add --no-cache zsh
	# --allow-scripts is required by newer npm, which otherwise skips the
	# package's postinstall (install.cjs) and leaves the install incomplete.
	npm --os=linux install --omit=dev --no-audit --no-fund \
		--allow-scripts=@anthropic-ai/claude-code \
		-g @anthropic-ai/claude-code
	apk cache clean
	rm -rf /usr/local/lib/node_modules/npm/man/ /root/.npm
	find /usr/local/lib/node_modules -type f -name '*.md' -delete
	# The launcher maps you to uid 1001 (node's image already has 1000).
	# Pinned so a different base can't quietly shift it.
	adduser -D -u 1001 claude
EOT

# Keep the base's PATH, which a custom base may have extended, rather than
# hardcoding the stock one. No pipe here: without pipefail, a failed run
# would slip past set -e and ship an empty PATH.
BASE_PATH=$(buildah run "$CONTAINER" printenv PATH)

buildah config \
	--author "Evan Carroll" \
	--env "PATH=$BASE_PATH" \
	--env "SHELL=/bin/zsh" \
	--env "DISABLE_TELEMETRY=1" \
	--env "DISABLE_AUTOUPDATER=1" \
	--cmd "" \
	--entrypoint '[ "/usr/local/bin/claude" ]' \
	--annotation "org.anthropic.claudecode.version=$CLAUDE_VERSION" \
	--annotation "org.opencontainers.image.title=claude-code" \
	--annotation "org.opencontainers.image.description=Claude Code on Alpine ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/EvanCarroll/coding-agent-podman" \
	--annotation "org.opencontainers.image.source=https://github.com/EvanCarroll/coding-agent-podman" \
	--annotation "org.opencontainers.image.documentation=https://github.com/EvanCarroll/coding-agent-podman/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "${IMAGE}:${CLAUDE_VERSION}"

echo "Built ${IMAGE}:${CLAUDE_VERSION} (also tagged ${IMAGE}:latest)"
echo "To use this image run: claude-podman --local"

echo "${IMAGE}:${CLAUDE_VERSION}" >&3
