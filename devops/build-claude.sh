#!/bin/sh
#
# Build the Claude Code image with buildah.
#
# Everything except the final image reference is written to stderr, so the
# only line on stdout is "claude-code:<version>" for callers (CI) to consume.

set -eu

exec 3>&1
exec 1>&2

CONTAINER=$(buildah from docker.io/node:current-alpine)
CLAUDE_VERSION=$(npm info @anthropic-ai/claude-code --json | jq .version -r)
IMAGE=claude-code

buildah run "$CONTAINER" sh <<-EOT
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
	adduser -D claude
EOT

buildah config \
	--author "Evan Carroll" \
	--env "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
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
