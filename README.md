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

Codex ships its own OS-level sandbox (landlock/seccomp). Inside podman that is
redundant — the container is already the boundary — and it frequently fails to
initialize under rootless podman. So `codex-podman` turns it off by default:

```sh
codex -c sandbox_mode="danger-full-access" -c approval_policy="never"
```

This is the posture OpenAI recommends *specifically* for containerized use. It
means codex will not prompt for approval and can write anywhere **inside the
container**, which is still only `$PWD` and `~/.codex` on your actual disk.

If you'd rather keep codex's internal sandbox as a second layer, pass
`--sandboxed` and it injects nothing:

```sh
codex-podman --sandboxed
```

Claude Code has no equivalent flag; it is confined by the container alone.

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

See `examples/init.sh` for an `--init-script` template.

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
| `--sandboxed` | | ✓ | Keep codex's own sandbox instead of relying on the container |
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

Images are built with [buildah](https://buildah.io/) — there is no Containerfile.

```sh
./devops/build-claude.sh   # prints claude-code:<version>
./devops/build-codex.sh    # prints codex:<version>
```

Each script prints exactly one line on stdout (the image reference) so CI can
consume it; all other output goes to stderr. Then run against the local build:

```sh
claude-podman --local
codex-podman --local
```

License
----

AGPL-3.0-or-later
