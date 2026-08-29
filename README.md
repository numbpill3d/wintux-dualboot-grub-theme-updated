# WinTux Dualboot Fullscreen GRUB Theme
![WinTux GRUB Theme Preview](repo-pictures/preview.gif)
Every time you boot up, make the choice.
A fullscreen GRUB theme inspired by the Matrix - because choosing between Windows and Linux should look as cool as it feels. No more staring at that ugly default boot menu from 1995.
***
## Install
Make the scripts executable (only needed once after cloning):
```bash
chmod u+x universal-installer.sh build.sh
```
Then run:
```bash
sudo ./universal-installer.sh
```
That's it. Script does everything - figures out your distro, installs what's needed, builds the theme, configures GRUB. Reboot and you're done.

Add `--auto` if you want zero prompts.
***
## Works On
Tested on basically everything with GRUB:
- Arch Linux
- Ubuntu / Debian / Mint
- Fedora / CentOS
- openSUSE
- Alpine
- Void Linux
- Gentoo
- Solus

If your distro has GRUB, it'll probably work. Let me know if it doesn't.
***
## What It Does
- Auto-detects your screen resolution and DPI
- Handles both ImageMagick 6 and 7 (no more version conflicts)
- Custom icons for Windows, Linux, and advanced options
- Scales properly on 1080p, 2K, and 4K displays
- Works with both UEFI and BIOS
- Zero manual config needed
***
## Custom Install Options
```bash
sudo ./universal-installer.sh --auto                    # full auto, no questions
sudo ./universal-installer.sh -r 2560x1440 -s 1.5       # force resolution/scaling
sudo ./universal-installer.sh --skip-deps               # skip dependency install
```

### Guarded EndeavourOS UEFI install (1920×1080)

This fork also includes a conservative, machine-specific installation path for
EndeavourOS systems using UEFI GRUB 2.14 and a 1920×1080 framebuffer. Unlike the
universal installer, it refuses to run unless it is root **and** receives an
explicit `--apply` flag.

Build the required theme assets first:

```bash
./build.sh 1920x1080 1
```

Review the script, then apply it:

```bash
sudo ./install-endeavouros-1920x1080.sh --apply
```

The guarded installer:

- verifies UEFI mode and required GRUB files before changing anything;
- serializes install/rollback operations with `flock`;
- creates root-only backups under `/var/backups/wintux-grub/`;
- preserves `/etc/default/grub`, `10_linux`, `30_uefi-firmware`, the active
  `grub.cfg`, and any existing theme at the same destination;
- enables `os-prober` and adds theme classes for Linux, advanced Linux options,
  and UEFI firmware;
- generates a same-filesystem candidate configuration and checks it with
  `grub-script-check`; and
- replaces `/boot/grub/grub.cfg` only after validation succeeds;
- attempts automatic recovery from ordinary command or validation failures and
  retains a root-only backup for manual recovery after power loss or `SIGKILL`.

Rollback uses the latest recorded backup by default:

```bash
sudo ./rollback-endeavouros.sh --apply
```

Or provide a specific backup directory as the second argument:

```bash
sudo ./rollback-endeavouros.sh --apply /var/backups/wintux-grub/backup-XXXXXXXX
```

The guarded scripts do not reboot the system. Windows detection still depends
on a working EFI installation and `os-prober`. Package upgrades can replace
files in `/etc/grub.d`, so review and rerun the guarded installer after relevant
GRUB package updates. This path has been validated for the configuration above;
other resolutions and distributions should continue to use the universal
installer or adapt the constants after careful review.
***
## Contributors

Thanks to everyone who has contributed to this project!

[![Contributors](https://contrib.rocks/image?repo=Harshil-Anuwadia/wintux-dualboot-grub-theme-updated)](https://github.com/Harshil-Anuwadia/wintux-dualboot-grub-theme-updated/graphs/contributors)

***
## 💖 Sponsors

Maintenance of this project is made possible by all the contributors and sponsors. Thank you for your support!

If you find this project useful, consider [sponsoring me on GitHub](https://github.com/sponsors/Harshil-Anuwadia) — it helps keep this and other projects alive. Every contribution, big or small, is deeply appreciated.

<a href="https://github.com/bijellj"><img src="https://github.com/bijellj.png?size=50" width="50px" alt="bijellj" /></a>

[![GitHub Sponsors](https://img.shields.io/github/sponsors/Harshil-Anuwadia?style=for-the-badge&logo=linux&logoColor=white&label=Current%20Sponsors&color=pink)](https://github.com/sponsors/Harshil-Anuwadia)

***
## Credits
**Original theme design:** [@AlexanderKh](https://github.com/AlexanderKh/wintux-dualboot-fullscreen-grub-theme)  
**Artwork:** [@ABOhiccups](https://www.pling.com/p/1497147)

**What I added:**
- Universal installer that actually works across distros
- Auto-detection for resolution, DPI, boot mode
- ImageMagick 6/7 compatibility fixes
- Support for 9+ different Linux distributions
- Various bug fixes and improvements
***
## Help Out
If this made your boot menu not suck:
- ⭐ Star the repo so others can find it
- 🐛 Report bugs in [Issues](../../issues)
- 🔀 Submit PRs for new distros or fixes
***
## License
See [LICENSE](LICENSE)
***
**Something broke?** Check [Issues](../../issues) or open a new one. I try to respond pretty quick.
## Star History
<a href="https://www.star-history.com/?repos=Harshil-Anuwadia%2Fwintux-dualboot-grub-theme-updated&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Harshil-Anuwadia/wintux-dualboot-grub-theme-updated&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Harshil-Anuwadia/wintux-dualboot-grub-theme-updated&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Harshil-Anuwadia/wintux-dualboot-grub-theme-updated&type=date&legend=top-left" />
 </picture>
</a>

***

## Session chooser mode (single-OS machines)

On a machine with only one operating system the dual-boot chooser is more
useful as a **desktop-session chooser**: the GRUB menu offers **KDE Plasma** and
**Sway**, both booting exactly the same kernel, and SDDM preselects whichever
one you picked.

![session plates](repo-pictures/sessions-preview.png)

### How it works

| Piece | What it does |
| --- | --- |
| `src/marks/` | The Sway tree and the KDE Plasma mark, as SVG |
| `src/build-session-plates.sh` | Renders each mark glowing in one of the WinTux hands, on the dimmed backdrop the stock `power.png` / `efi.png` plates already use |
| `build.sh` | Picks the plates up automatically and emits `icons/plasma.png` and `icons/sway.png` alongside the stock icons |
| `sessions/09_wintux_sessions` | A `grub.d` snippet that emits the two entries |
| `sessions/wintux-session-apply` | Reads the choice back before SDDM starts |
| `sessions/sddm-10-wintux-session.conf` | `sddm.service` drop-in that runs it |

The two GRUB entries are **not** hand-written. `09_wintux_sessions` runs the
distribution's own `/etc/grub.d/10_linux` with an overridden
`GRUB_DISTRIBUTOR`, keeps the first (top-level) menuentry it emits, and rewrites
only the title. The kernel path, the initrd order, the root UUID and `resume=`
are therefore always whatever `10_linux` would have generated, and kernel or
initramfs changes need no edits here.

`GRUB_DISTRIBUTOR` also decides the entry's first `--class`, which is exactly
how the theme picks its plate: `Plasma` → `--class plasma` → `icons/plasma.png`.

The only thing that differs between the two entries is one kernel argument:

```
systemd.setenv=WINTUX_SESSION=plasma      # or =sway
```

`wintux-session-apply` runs as an `ExecStartPre=` for `sddm.service`, reads that
argument back out of `/proc/cmdline`, resolves it to a session `.desktop` file
and writes it into SDDM's `state.conf` as the last-used session — which is what
the greeter preselects. Your login prompt is untouched; only the session
dropdown moves. The `ExecStartPre=` is prefixed with `-`, so a failure here can
never keep the display manager from starting.

### Install (EndeavourOS / UEFI / GRUB 2.14 / 1920x1080 / SDDM)

```bash
./build.sh 1920x1080 2.6
sudo ./install-sessions-endeavouros.sh --apply
```

The installer reuses the guarded machinery from
`install-endeavouros-1920x1080.sh`: `flock`, root-only backups under
`/var/backups/wintux-sessions/`, a same-filesystem candidate config checked with
`grub-script-check`, and automatic recovery if any step fails. It additionally
verifies that the generated config really contains both session entries with
their markers before replacing `grub.cfg`.

It sets `GRUB_TIMEOUT=10` (a chooser you cannot see is pointless),
`GRUB_GFXMODE=1920x1080`, points `GRUB_THEME` at the new theme and comments out
`GRUB_BACKGROUND`, which would otherwise conflict. `os-prober` is left alone —
there is no second OS to find. `GRUB_DEFAULT=0` selects the first entry, KDE
Plasma; swap the two `emit` lines at the bottom of `09_wintux_sessions` to make
Sway the default instead.

Menu order afterwards: **KDE Plasma**, **Sway**, the stock EndeavourOS entry,
Advanced options, UEFI firmware. The stock entry is left in place deliberately —
it boots with no session marker at all, so SDDM behaves exactly as it did
before, which makes it the safety net if anything about the chooser misbehaves.

### Try it without rebooting

```bash
sudo /usr/local/bin/wintux-session-apply sway
sudo cat /var/lib/sddm/state.conf
```

### Uninstall

```bash
sudo ./rollback-sessions-endeavouros.sh --apply
```

### Adding another session

Add an `emit <key> <Distributor> '<Menu title>'` line to
`sessions/09_wintux_sessions`, a matching `case` arm in
`sessions/wintux-session-apply`, a `<key>.svg` in `src/marks/`, and a `plate`
line in `src/build-session-plates.sh`. The `--class` GRUB derives from the
distributor name has to match the icon filename.
