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

Both images are rebuilt daily against the current upstream release, so `:latest`
tracks the newest Claude Code / Codex without you updating anything.

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

Everything else in your home directory — SSH keys, cloud credentials, browser
profiles, other projects — is simply not present in the container. The agent can
only execute the files that exist in the image.

Both images run under rootless podman *and* as a non-root user inside the
container, with `--userns=keep-id` so files the agent creates in `$PWD` come out
owned by you rather than by root. The agents are locked down hard enough that
they can't even update themselves.

Neither image ships `git` — see [Customizing the runtime](#customizing-the-runtime)
if you want it.

Signing in
----

**Claude Code** stores its credentials in `$HOME/.claude.json` and
`$HOME/.claude`, both of which are mounted, so signing in once persists.

**Codex** is slightly awkward the first time. `codex login` completes an OAuth
handshake against `localhost:1455`, and that callback can't reach your host
browser from inside a rootless container. Two ways around it:

```sh
# Option 1 (simplest): log in once on the host. The token lands in
# ~/.codex/auth.json, which the container mounts.
codex login

# Option 2: publish the callback port so the containerized login works.
codex-podman --login login
```

After either, `~/.codex/auth.json` exists and `codex-podman` just works. An
`OPENAI_API_KEY` also works if you'd rather not use OAuth at all:

```sh
codex-podman --podman-arg "-e OPENAI_API_KEY=$OPENAI_API_KEY"
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
--podman-arg   ARG         # passes ARG straight through to podman (repeatable)
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
	--podman-arg "-v $HOME/.kube/config:/home/claude/.kube/config"
```

The same for codex — note the different home directory inside the container:

```sh
codex-podman \
	--apk-packages kubectl \
	--podman-arg "-v $HOME/.kube/config:/home/codex/.kube/config"
```

See `examples/init.sh` for an `--init-script` template.

Options
----

| Option | Claude | Codex | Description |
| --- | :---: | :---: | --- |
| `--local` | ✓ | ✓ | Use the locally built image instead of pulling from ghcr.io |
| `--apk-packages LIST` | ✓ | ✓ | Install extra Alpine packages (comma or space separated) |
| `--init-script FILE` | ✓ | ✓ | Copy FILE into the container and run it as root |
| `--podman-arg ARG` | ✓ | ✓ | Pass an extra argument to `podman run` (repeatable) |
| `--self-update` | ✓ | ✓ | Replace the installed launcher with the latest from GitHub |
| `--help` | ✓ | ✓ | Show usage |
| `--sandboxed` | | ✓ | Keep codex's own sandbox instead of relying on the container |
| `--login` | | ✓ | Publish port 1455 so `codex login` can call back to your browser |

Launcher options must come first: the first unrecognized argument, and
everything after it, is forwarded to the agent itself.

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
