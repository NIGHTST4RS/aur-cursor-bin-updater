# AUR Cursor AI Binary Package Updater

Automated maintenance system for the `cursor-ai-bin` AUR package. This repository monitors Cursor IDE releases and keeps an AUR-ready `PKGBUILD` updated.

## What this repository does

This project is an automation repo, not a manual install guide. It:

- Checks for new Cursor stable releases on a schedule.
- Updates `PKGBUILD` version, commit, and source checksum.
- Publishes updates to AUR from `main`.
- Uses Cursor's bundled runtime from the upstream `.deb` package to avoid system-Electron mismatch issues that can break Git/containers/Remote SSH.
- Installs a `cursor` launcher wrapper that loads `~/.config/cursor-flags.conf` and delegates to Cursor's upstream launcher.
- Pins third-party GitHub Actions to immutable commit SHAs.
- Validates update API `version`/`commit` formats before generating package updates.
- Uses Dependabot to keep pinned GitHub Actions dependencies updated.

## Install (end users)

```bash
# Using yay
yay -S cursor-ai-bin

# Using paru
paru -S cursor-ai-bin

# Using makepkg (manual)
git clone https://aur.archlinux.org/cursor-ai-bin.git
cd cursor-ai-bin
makepkg -si
```

## Repository layout

| File | Purpose |
|------|---------|
| `.github/workflows/update-aur.yml` | Scheduled update + publish workflow |
| `PKGBUILD.sed` | Template used by the workflow |
| `PKGBUILD` | Current generated package recipe |
| `test_bash_workflow.sh` | Local dry-run generator/validator |
| `TESTING.md` | Testing guide and checklist |

## Automated workflow

1. Read current package version/commit from `PKGBUILD`.
2. Query AUR metadata and Cursor update API.
3. Download latest `.deb` and compute SHA512.
4. Regenerate `PKGBUILD` from `PKGBUILD.sed`.
5. Validate generated fields.
6. Commit to the repo branch.
7. Publish to AUR (on `main`; skipped on `development`).

When triggered manually, `workflow_dispatch` also supports `force_publish=true` to publish even if versions already match.
The workflow also auto-publishes when the AUR package does not exist yet (initial bootstrap).

## Branch behavior

- `development`: update + validation only, no AUR publish.
- `main`: update + AUR publish.

## Local testing

```bash
./test_bash_workflow.sh
```

Optional checks:

```bash
makepkg --verifysource --noconfirm
makepkg -s
```

## Why bundled runtime

Cursor staff has confirmed that community AUR packages can break if they run against a different system Electron version than Cursor's tested runtime for that release. This package keeps the runtime bundled from Cursor's official `.deb` build to avoid those mismatches.

## Troubleshooting T3 Code launch behavior

If Cursor opens fine from your terminal but T3 Code hangs or fails to launch it, the issue is usually the CLI entrypoint, not the Electron runtime itself.

- T3 Code launches editors through CLI commands and expects non-blocking launcher behavior.
- `cursor-ai-bin` now installs `/usr/bin/cursor` as a launcher wrapper that forwards to Cursor's upstream launcher and loads `~/.config/cursor-flags.conf`.
- If `cursor` points directly to the raw app binary instead of the launcher path, behavior can differ (TTY attachment, ignored flags, or editor integration issues).

Quick checks:

```bash
command -v cursor
readlink -f "$(command -v cursor)"
file "$(command -v cursor)"
```

Expected:

- `command -v cursor` resolves to `/usr/bin/cursor`
- `file ...` reports a shell script launcher (not only an ELF binary target)

Validate flags file format:

```bash
mkdir -p ~/.config
printf '%s\n' '--ozone-platform=wayland' > ~/.config/cursor-flags.conf
```

Update/reinstall package after launcher changes:

```bash
yay -Syu cursor-ai-bin
# or
paru -Syu cursor-ai-bin
```

If T3 Code still fails:

- Ensure `cursor` is available in the same `PATH` seen by T3 Code.
- Set editor selection to Cursor again inside T3 Code so it re-resolves the command.
- Test with explicit command path `/usr/bin/cursor`.

## Contributing

1. Fork the repository.
2. Create a branch from `development`.
3. Run `./test_bash_workflow.sh`.
4. Open a PR against `development`.

## Links

- [Cursor official site](https://www.cursor.com)
- [AUR cursor-ai-bin package](https://aur.archlinux.org/packages/cursor-ai-bin)
- [Arch Linux AUR guidelines](https://wiki.archlinux.org/title/AUR_submission_guidelines)
