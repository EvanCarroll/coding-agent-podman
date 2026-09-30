coding-agent-podman
====

Coding agents for the security-conscious: run
[Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
(Anthropic) or [Codex](https://developers.openai.com/codex) (OpenAI / ChatGPT)
inside a rootless [podman](https://podman.io/) container.

Each agent gets its own minimal Alpine image and its own launcher. Nothing is
shared between them, and neither image contains anything the agent doesn't need.

| Agent | Launcher | Image |
| --- | --- | --- |
| Claude Code | `claude-podman` | `ghcr.io/evancarroll/coding-agent-podman/claude-code` |
| Codex | `codex-podman` | `ghcr.io/evancarroll/coding-agent-podman/codex` |

Both images are rebuilt daily against the current upstream release, and the
launchers check the registry on every start (`--pull=newer`), so you always run
the newest Claude Code / Codex without updating anything. Offline, they fall
back to the image you already have.

Installation
----

First [install podman](https://podman.io/docs/installation). Then install
whichever launcher you want — they're single self-contained shell scripts.

**Claude Code:**

```sh
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/EvanCarroll/coding-agent-podman/refs/heads/main/bin/claude |
  sudo tee /usr/local/bin/claude-podman >/dev/null
sudo chmod a+x /usr/local/bin/claude-podman
```

**Codex:**

```sh
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/EvanCarroll/coding-agent-podman/refs/heads/main/bin/codex |
  sudo tee /usr/local/bin/codex-podman >/dev/null
sudo chmod a+x /usr/local/bin/codex-podman
```

Or, from a clone of this repository, install both at once:

```sh
make
```

`make` copies `bin/claude` and `bin/codex` to `/usr/local/bin/claude-podman` and
`/usr/local/bin/codex-podman` — the same names the curl commands above use, so
the two methods are interchangeable. `make install-claude` / `make install-codex`
install just one, `make uninstall` removes them, and `PREFIX` or `BINDIR` retarget
the destination (`make PREFIX=$HOME/.local SUDO=` needs no root).

Now just run `claude-podman` or `codex-podman` from the directory you want the
agent to work in. Later, `claude-podman --self-update` / `codex-podman --self-update`
refreshes the launcher itself.

Benefits
----

The agent only gets file access to:

| | Claude Code | Codex |
| --- | --- | --- |
| Working directory | `$PWD` | `$PWD` |
| Credentials + config | `$HOME/.claude`, `$HOME/.claude.json` | `$HOME/.codex` |
| Agent config (read-only) | `settings.json`, `CLAUDE.md`, `plugins/`, `agents/`, `commands/`, `skills/` under `~/.claude` | `config.toml`, `AGENTS.md`, `rules/` under `~/.codex` |
| Git config (read-only) | `~/.gitconfig`, `~/.config/git/config` | `~/.gitconfig`, `~/.config/git/config` |

Everything else in your home directory — SSH keys, cloud credentials, browser
profiles, other projects — is simply not present in the container. The agent can
only execute the files that exist in the image.

Both images run under rootless podman *and* as a non-root user inside the
container, with `--userns=keep-id` so files the agent creates in `$PWD` come out
owned by you rather than by root. The agents are locked down hard enough that
they can't even update themselves.

The git config is there so commits carry your name and aliases work. It's
mounted read-only, and any credential helpers it names (`gh`, `glab`, …) don't
exist in the container, so the agent has no git credentials.

The agent config is read-only because it's what the agent on your *host* runs
code from (hooks, status lines, MCP servers, plugins, codex's `notify` and
execpolicy rules) or takes instructions from. If it were writable, an agent in
the container could plant something that runs outside the container the next
time you use `claude` or `codex` directly. The rest of `~/.claude` and `~/.codex`
(credentials, history, sessions) stays writable. Missing files and directories
in that list are created empty on first run, so the agent can't create them
either. The effect: change settings, install plugins and edit `CLAUDE.md` /
`AGENTS.md` on the host, not from inside the container. Codex can't save its
"trust this folder" answer to a read-only `config.toml`, so `codex-podman`
records that trust itself when it starts in a new folder.

What is still writable and can reach the host:

- `~/.claude.json` holds Claude Code's user and per-project `mcpServers`, and
  Claude rewrites the file constantly, so it can't be made read-only.
- `$PWD` is your project. `.git/hooks`, `.git/config`, `.claude/`, `.codex/`,
  `.mcp.json`, `.envrc`, `Makefile` and the like are all writable, and all run
  on the host later. Review the diff before running anything in it outside the
  container.

Neither image ships `git` — see [Customizing the runtime](#customizing-the-runtime)
if you want it.

Signing in
----

**Claude Code** stores its credentials in `$HOME/.claude.json` and
`$HOME/.claude`, both of which are mounted, so signing in once persists. There
is no browser in the container, so `/login` falls back to printing a URL and
asking you to paste back the code the site gives you. That works everywhere,
but if you'd rather get the normal "browser opens, login completes" flow:

```sh
# Option 1: log in once on the host (run claude, then /login). The token
# lands in ~/.claude/.credentials.json, which the container mounts.
claude

# Option 2: paste the code. No flags needed; works on remote/headless hosts.
claude-podman

# Option 3: open the URL in your host browser and route the OAuth callback back
# into the container. Requires pasta (podman's default since 5.0).
claude-podman --login
```

`--login` is more involved than codex's, because claude's callback server
listens on a *random* port. The launcher sets `$BROWSER` in the container to a
script that hands the URL to the host, which opens it with `xdg-open` (or
prints it if there's no `xdg-open`), and runs pasta with `-t auto` so whatever
port claude binds is forwarded from the host. That forwards *every* port the
container listens on, on all of the host's IPv4 addresses, and turns IPv6 off
for the session, so use `--login` to log in and then restart without it.

**Codex** is slightly awkward the first time. `codex login` starts a server on
`localhost:1455` and waits for your browser to deliver an OAuth callback to it.
Because codex binds that server to the container's loopback address, publishing
the port alone is not enough — pasta hands inbound connections to the
container's public address, so the browser gets a connection reset. Three ways
around it:

```sh
# Option 1 (simplest): log in once on the host. The token lands in
# ~/.codex/auth.json, which the container mounts.
codex login

# Option 2: no callback port at all — codex prints a code to enter in your
# browser. Good for remote or headless hosts.
codex-podman login --device-auth

# Option 3: publish the callback port and route it to the container's loopback,
# which is what --login now does. Requires pasta (podman's default since 5.0).
codex-podman --login login
```

After either, `~/.codex/auth.json` exists and `codex-podman` just works. An
`OPENAI_API_KEY` also works if you'd rather not use OAuth at all:

```sh
codex-podman --podman-arg "--env=OPENAI_API_KEY=$OPENAI_API_KEY"
```

Sandboxing
----

By default both agents still ask before doing anything risky, as they do outside
a container. `--yolo` turns that off for either one.

| | Claude default | Claude `--yolo` | Codex default | Codex `--yolo` |
| --- | --- | --- | --- | --- |
| Passed to the agent | nothing | `--dangerously-skip-permissions --settings '{"skipDangerousModePermissionPrompt":true}'` | `-c sandbox_mode="workspace-write" -c approval_policy="on-request"` | `-c sandbox_mode="danger-full-access" -c approval_policy="never"` |
| What holds it back | permission prompts | nothing but the container | codex's sandbox (bubblewrap), prompts to leave it | nothing but the container |
| Edits in `$PWD` | asks | allowed | allowed | allowed |
| Shell commands | read-only ones run, the rest ask | allowed | run inside the sandbox | allowed |
| Writes elsewhere in the container | asks | allowed | asks | allowed |
| Network | allowed once the command or fetch is approved | allowed | asks | allowed |
| "Don't ask again" | saved to `$PWD/.claude/settings.local.json`, so your host claude also honors it | n/a | this session only (`~/.codex/rules/` is read-only) | n/a |

The two defaults differ in how they hold the agent back. Claude asks before each
action and has no sandbox, so once you approve a command it can do anything the
container allows, network included. Codex runs commands without asking but
inside its sandbox, and asks only when a command needs to leave it: to write
outside the workspace or reach the network. Your own settings still apply on
top: a `permissions` block or `defaultMode` in `~/.claude/settings.json` changes
what Claude asks about.

The two `--yolo` modes end up the same: no prompts, no sandbox inside the
container, full network. The difference is only what gets switched off. Claude
never had a sandbox, so `--yolo` just drops its prompts, and the launcher also
skips its one-time warning dialog. Codex loses its sandbox and its prompts. In
both, the container is the only boundary, and whatever stays writable (see
[Benefits](#benefits): `$PWD`, `~/.claude.json`, the rest of `~/.codex`) is
open to the agent without a prompt.

`codex-podman` passes codex's defaults explicitly even though codex would pick
them anyway: without any `-c`, codex starts a background server, which can't
run under podman.

Customizing the runtime
----

Need to add packages to the container, or run an init script? No problem — both
launchers support the same options.

```
--apk-packages foo,bar,baz # adds packages foo, bar, baz, with apk
--init-script  ./foobar.sh # copies foobar.sh into the container and runs it as root
--podman-arg   ARG         # passes ARG to podman run as ONE argument (repeatable)
```

Neither image includes `git`, so a common one is:

```sh
claude-podman --apk-packages git
```

For example, let's say you're using kubernetes and you do want the agent to be
able to troubleshoot it:

```sh
claude-podman \
	--apk-packages kubectl \
	--podman-arg "--volume=$HOME/.kube/config:/home/claude/.kube/config:ro"
```

The same for codex — note the different home directory inside the container:

```sh
codex-podman \
	--apk-packages kubectl \
	--podman-arg "--volume=$HOME/.kube/config:/home/codex/.kube/config:ro"
```

See `examples/init.sh` for an `--init-script` template. Packages are
installed and init scripts run on every start, so for anything heavy, like a
language toolchain, bake it into the image instead; see
[Customizing the image](#customizing-the-image).

Options
----

| Option | Claude | Codex | Description |
| --- | :---: | :---: | --- |
| `--local` | ✓ | ✓ | Use the locally built image instead of pulling from ghcr.io |
| `--apk-packages LIST` | ✓ | ✓ | Install extra Alpine packages (comma or space separated) |
| `--init-script FILE` | ✓ | ✓ | Copy FILE into the container and run it as root |
| `--podman-arg ARG` | ✓ | ✓ | Pass one extra argument to `podman run` (repeatable; use `--flag=value` forms) |
| `--self-update` | ✓ | ✓ | Replace the installed launcher with the latest from GitHub |
| `--help` | ✓ | ✓ | Show usage |
| `--yolo` | ✓ | ✓ | No permission prompts; for codex, also no sandbox inside the container |
| `--login` | ✓ | ✓ | Make browser OAuth login work: codex's fixed port 1455, or for Claude, open the URL on the host and forward its random callback port |

Launcher options must come first: the first unrecognized argument, and
everything after it, is forwarded to the agent itself.

Each `--podman-arg` is passed as exactly one argument, so paths with spaces
work, but `"-v a:b"` does not. Write `"--volume=a:b"` or repeat the option
(`--podman-arg -v --podman-arg a:b`).

Packages and `--init-script` are installed before the agent starts, and a
failure stops the launch. The container is removed when the agent exits,
you close the terminal, or you press Ctrl-C during setup. Without a terminal,
the launchers run the agent non-interactively, so pipes work:

```sh
git diff | claude-podman -p "review this diff"
```

Building locally
----

Images are built by [buildah](https://buildah.io/) scripts, not from a
Containerfile. From a clone:

```sh
make images   # or make image-claude / make image-codex
```

That runs `./devops/build-claude.sh` and `./devops/build-codex.sh`, which you
can also run directly. Each prints exactly one line on stdout (the image
reference, e.g. `claude-code:<version>`) so CI can consume it; all other output
goes to stderr. Then run against the local build:

```sh
claude-podman --local
codex-podman --local
```

### Customizing the image

`--apk-packages` and `--init-script` run on every start, which is fine for a
package or two but far too slow for a toolchain. To bake one in, layer a
Containerfile of your own under the images. For example, Rust nightly:

```sh
make images CONTAINERFILE=examples/Containerfile.rust-nightly
claude-podman --local
```

Copy it to `./Containerfile` (gitignored, so it stays yours) and a plain
`make images` picks it up; `make images CONTAINERFILE=` builds the stock images
again. Start your own with:

```containerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
```

The build fills in each agent's usual Alpine base (`node:current-alpine` for
Claude Code, `alpine:latest` for Codex), so one file serves both. The agent is
installed on top, so keep it Alpine and don't add users; the agents claim uids
1000 and 1001. A hardcoded `FROM` works too, but then that base has to meet
those needs itself, including npm for Claude Code.

The build scripts read the same settings from the environment, and CI sets
none of them:

| Variable | Effect |
| --- | --- |
| `BASE_IMAGE` | Build on this image instead of the agent's usual base |
| `CONTAINERFILE` | Build this file on `BASE_IMAGE` first, then the agent on the result |
| `NO_CACHE=1` | Rebuild the Containerfile from scratch; its steps are otherwise cached for up to a week |

A custom build replaces your local `claude-code:latest` / `codex:latest`, so
`--local` runs whichever you built last.

Cargo's download cache lives in the container and goes when it does. To keep
it between sessions, give it a named volume rather than mounting your own
`~/.cargo`, which holds your crates.io token and binaries your host runs (for
codex, the path is `/home/codex/.cargo`):

```sh
claude-podman --local --podman-arg "--volume=cargo-home:/home/claude/.cargo:U"
```

License
----

AGPL-3.0-or-later
