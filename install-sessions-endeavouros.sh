#!/usr/bin/env bash
# Install the WinTux session chooser on this machine.
#
# There is no second operating system on this disk, so the WinTux dual-boot
# chooser is repurposed as a desktop-session chooser: the GRUB menu offers
# "KDE Plasma" and "Sway", both booting the same kernel, and SDDM preselects
# whichever one was picked.
#
# This is the guarded, machine-specific path (EndeavourOS, UEFI, GRUB 2.14,
# 1920x1080, SDDM).  It refuses to run without root and an explicit --apply.
#
#   ./build.sh 1920x1080 2.6
#   sudo ./install-sessions-endeavouros.sh --apply
#
# Undo with rollback-sessions-endeavouros.sh --apply
set -Eeuo pipefail
readonly PATH=/usr/bin
export PATH

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly THEME_SOURCE="$SCRIPT_DIR/build/WinTux Dualboot Fullscreen 1920x1080-2.6x/win-tux-dualboot-fullscreen"
readonly THEME_DEST="/boot/grub/themes/wintux-sessions"
readonly DEFAULT_GRUB="/etc/default/grub"
readonly GRUB_CFG="/boot/grub/grub.cfg"
readonly BACKUP_ROOT="/var/backups/wintux-sessions"

readonly GRUBD_SESSIONS="/etc/grub.d/09_wintux_sessions"
readonly APPLY_BIN="/usr/local/bin/wintux-session-apply"
readonly SDDM_DROPIN_DIR="/etc/systemd/system/sddm.service.d"
readonly SDDM_DROPIN="$SDDM_DROPIN_DIR/10-wintux-session.conf"

# name:destination:mode - the files this installer adds, in backup order
readonly ADDED_FILES=(
  "09_wintux_sessions:$GRUBD_SESSIONS:755"
  "wintux-session-apply:$APPLY_BIN:755"
  "sddm-dropin.conf:$SDDM_DROPIN:644"
)

candidate=""
theme_stage=""
theme_hold=""
backup_dir=""
default_stage=""
linux_stage=""
uefi_stage=""
backup_ready=0
theme_was_absent=0
install_complete=0

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

validate_secure_directory() {
  local path=$1 mode permissions resolved
  [[ -d $path && ! -L $path ]] || fail "directory is missing or is a symlink: $path"
  resolved=$(realpath -e -- "$path")
  [[ $resolved == "$path" ]] || fail "directory does not resolve to its expected path: $path -> $resolved"
  [[ $(stat -c %u -- "$path") == 0 ]] || fail "directory is not root-owned: $path"
  mode=$(stat -c %a -- "$path")
  permissions=$((8#$mode))
  (( (permissions & 8#022) == 0 )) || fail "directory is group/world writable: $path"
}

prepare_secure_directory() {
  local path=$1 mode=$2 parent
  if [[ -e $path || -L $path ]]; then
    validate_secure_directory "$path"
  else
    parent=$(dirname -- "$path")
    validate_secure_directory "$parent"
    install -d -m "$mode" -o root -g root -- "$path"
    validate_secure_directory "$path"
  fi
}

validate_plain_theme_tree() {
  local path=$1 unsafe
  unsafe=$(find "$path" \( -type l -o \( ! -type d -a ! -type f \) \) -print -quit)
  [[ -z $unsafe ]] || fail "theme contains a symlink or special file: $unsafe"
}

validate_secure_theme_tree() {
  local path=$1 unsafe
  validate_plain_theme_tree "$path"
  unsafe=$(find "$path" \( ! -user root -o -perm /022 \) -print -quit)
  [[ -z $unsafe ]] || fail "theme contains an unsafe owner or permission: $unsafe"
}

validate_secure_file() {
  local path=$1 mode permissions
  [[ -f $path && ! -L $path ]] || fail "required regular file is missing or is a symlink: $path"
  [[ $(stat -c %u -- "$path") == 0 ]] || fail "file is not root-owned: $path"
  mode=$(stat -c %a -- "$path")
  permissions=$((8#$mode))
  (( (permissions & 8#022) == 0 )) || fail "file is group/world writable: $path"
}

validate_grub_executable() {
  local path=$1 resolved parent
  if [[ -L $path ]]; then
    [[ $(stat -c %u -- "$path") == 0 ]] || fail "GRUB executable symlink is not root-owned: $path"
    resolved=$(realpath -e -- "$path")
    validate_secure_file "$resolved"
    parent=$(dirname -- "$resolved")
    while :; do
      validate_secure_directory "$parent"
      [[ $parent == / ]] && break
      parent=$(dirname -- "$parent")
    done
  else
    validate_secure_file "$path"
  fi
}

validate_grub_inputs() {
  local path
  validate_secure_file "$DEFAULT_GRUB"
  for path in /etc/grub.d/*; do
    [[ -e $path || -L $path ]] || continue
    if [[ -x $path ]]; then
      validate_grub_executable "$path"
    fi
  done
}

atomic_install() {
  local source=$1 destination=$2 mode=$3 directory temporary
  directory=$(dirname -- "$destination")
  temporary=$(mktemp "$directory/.wintux-$(basename -- "$destination").XXXXXXXX")
  install -m "$mode" -o root -g root -- "$source" "$temporary"
  mv -fT -- "$temporary" "$destination"
}

# Put back whatever was at each added file's destination before this run.
restore_added_files() {
  local entry name destination mode
  for entry in "${ADDED_FILES[@]}"; do
    IFS=: read -r name destination mode <<<"$entry"
    if [[ -f $backup_dir/$name.previous ]]; then
      atomic_install "$backup_dir/$name.previous" "$destination" "$mode" || true
    elif [[ -f $backup_dir/$name.absent ]]; then
      rm -f -- "$destination" || true
    fi
  done
}

restore_after_error() {
  local status=$?
  trap - EXIT INT TERM
  if (( status != 0 && backup_ready == 1 && install_complete == 0 )); then
    printf 'Install failed; restoring the previous state from %s\n' "$backup_dir" >&2
    atomic_install "$backup_dir/grub.default" "$DEFAULT_GRUB" 644 || true
    atomic_install "$backup_dir/10_linux" /etc/grub.d/10_linux 755 || true
    atomic_install "$backup_dir/30_uefi-firmware" /etc/grub.d/30_uefi-firmware 755 || true
    atomic_install "$backup_dir/grub.cfg" "$GRUB_CFG" 600 || true
    restore_added_files
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [[ -n $theme_hold && -d $theme_hold/original ]]; then
      rm -rf -- "$THEME_DEST"
      mv -- "$theme_hold/original" "$THEME_DEST" || true
    elif (( theme_was_absent == 1 )); then
      rm -rf -- "$THEME_DEST"
    fi
  fi
  [[ -n $candidate ]] && rm -f -- "$candidate"
  [[ -n $default_stage ]] && rm -f -- "$default_stage"
  [[ -n $linux_stage ]] && rm -f -- "$linux_stage"
  [[ -n $uefi_stage ]] && rm -f -- "$uefi_stage"
  [[ -n $theme_stage ]] && rm -rf -- "$theme_stage"
  [[ -n $theme_hold ]] && rm -rf -- "$theme_hold"
  exit "$status"
}
trap restore_after_error EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ ${EUID} -eq 0 ]] || fail "run with sudo"
[[ ${1:-} == "--apply" ]] || fail "refusing to change GRUB without the --apply flag"
(( $# == 1 )) || fail "usage: sudo $0 --apply"
[[ -d /sys/firmware/efi ]] || fail "this machine is not currently booted in UEFI mode"
[[ -d "$THEME_SOURCE" && -f "$THEME_SOURCE/theme.txt" ]] || \
  fail "built theme is missing, run ./build.sh 1920x1080 2.6 first: $THEME_SOURCE"
for icon in plasma sway gnu-linux; do
  [[ -f "$THEME_SOURCE/icons/$icon.png" ]] || fail "built theme has no icons/$icon.png"
done
for command in grub-mkconfig grub-script-check python flock install mktemp realpath find stat systemctl getent; do
  command -v "$command" >/dev/null || fail "$command is missing"
done
for file in "$DEFAULT_GRUB" /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware "$GRUB_CFG"; do
  validate_secure_file "$file"
done
for source in sessions/09_wintux_sessions sessions/wintux-session-apply sessions/sddm-10-wintux-session.conf; do
  [[ -f "$SCRIPT_DIR/$source" && ! -L "$SCRIPT_DIR/$source" ]] || fail "missing installer payload: $source"
done

# The session chooser is only meaningful if SDDM and both sessions are present.
systemctl list-unit-files sddm.service >/dev/null 2>&1 || fail "sddm.service is not installed"
[[ -f /usr/share/wayland-sessions/plasma.desktop ]] || fail "plasma.desktop is missing"
[[ -f /usr/share/wayland-sessions/sway.desktop ]] || fail "sway.desktop is missing"
getent passwd sddm >/dev/null || fail "the sddm user does not exist"

validate_secure_directory /etc
validate_secure_directory /etc/default
validate_secure_directory /etc/grub.d
validate_secure_directory /etc/systemd/system
validate_secure_directory /run
validate_secure_directory /run/lock
validate_secure_directory /boot
validate_secure_directory /boot/grub
validate_secure_directory /usr/local/bin
validate_grub_inputs
validate_plain_theme_tree "$THEME_SOURCE"

exec 9>/run/lock/wintux-sessions.lock
flock -n 9 || fail "another WinTux operation is already running"
prepare_secure_directory /boot/grub/themes 755
prepare_secure_directory "$SDDM_DROPIN_DIR" 755

validate_secure_directory /var
prepare_secure_directory /var/backups 755
prepare_secure_directory "$BACKUP_ROOT" 700
chmod 700 "$BACKUP_ROOT"
validate_secure_directory "$BACKUP_ROOT"
backup_dir=$(mktemp -d "$BACKUP_ROOT/backup-XXXXXXXX")
chmod 700 "$backup_dir"
cp -a -- "$DEFAULT_GRUB" "$backup_dir/grub.default"
cp -a -- /etc/grub.d/10_linux "$backup_dir/10_linux"
cp -a -- /etc/grub.d/30_uefi-firmware "$backup_dir/30_uefi-firmware"
cp -a -- "$GRUB_CFG" "$backup_dir/grub.cfg"
for entry in "${ADDED_FILES[@]}"; do
  IFS=: read -r name destination mode <<<"$entry"
  if [[ -e $destination || -L $destination ]]; then
    [[ -f $destination && ! -L $destination ]] || fail "existing path is not a regular file: $destination"
    cp -a -- "$destination" "$backup_dir/$name.previous"
  else
    : > "$backup_dir/$name.absent"
    chmod 600 "$backup_dir/$name.absent"
  fi
done
backup_ready=1
latest_tmp=$(mktemp "$BACKUP_ROOT/.LATEST.XXXXXXXX")
printf '%s\n' "$backup_dir" > "$latest_tmp"
chmod 600 "$latest_tmp"
chown root:root "$latest_tmp"
mv -fT -- "$latest_tmp" "$BACKUP_ROOT/LATEST"

validate_plain_theme_tree "$THEME_SOURCE"
theme_stage=$(mktemp -d "$(dirname -- "$THEME_DEST")/.wintux-stage-XXXXXXXX")
cp -a -- "$THEME_SOURCE/." "$theme_stage/"
chown -R root:root "$theme_stage"
find "$theme_stage" -type d -exec chmod 755 {} +
find "$theme_stage" -type f -exec chmod 644 {} +
validate_secure_theme_tree "$theme_stage"

if [[ -e $THEME_DEST || -L $THEME_DEST ]]; then
  [[ -d $THEME_DEST && ! -L $THEME_DEST ]] || fail "theme destination is not a regular directory: $THEME_DEST"
  validate_secure_theme_tree "$THEME_DEST"
  cp -a -- "$THEME_DEST" "$backup_dir/theme.previous"
  theme_hold=$(mktemp -d "$(dirname -- "$THEME_DEST")/.wintux-hold-XXXXXXXX")
  mv -- "$THEME_DEST" "$theme_hold/original"
else
  theme_was_absent=1
fi
mv -- "$theme_stage" "$THEME_DEST"
theme_stage=""

default_stage=$(mktemp /etc/default/.grub.wintux.XXXXXXXX)
linux_stage=$(mktemp /etc/grub.d/.10_linux.wintux.XXXXXXXX)
uefi_stage=$(mktemp /etc/grub.d/.30_uefi-firmware.wintux.XXXXXXXX)
install -m 644 -o root -g root -- "$DEFAULT_GRUB" "$default_stage"
install -m 755 -o root -g root -- /etc/grub.d/10_linux "$linux_stage"
install -m 755 -o root -g root -- /etc/grub.d/30_uefi-firmware "$uefi_stage"

# GRUB_TIMEOUT is deliberately generous: a chooser you cannot see is pointless,
# and the stock EndeavourOS value here was 1 second.  os-prober is left alone --
# there is no second OS on this disk.  GRUB_DEFAULT=0 selects the first entry
# emitted by 09_wintux_sessions, which is KDE Plasma.
python - "$default_stage" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
text = path.read_text()
settings = {
    "GRUB_DEFAULT": "'0'",
    "GRUB_TIMEOUT": "10",
    "GRUB_TIMEOUT_STYLE": "menu",
    "GRUB_GFXMODE": '"1920x1080"',
    "GRUB_GFXPAYLOAD_LINUX": "keep",
    "GRUB_THEME": '"/boot/grub/themes/wintux-sessions/theme.txt"',
}
for key, value in settings.items():
    pattern = rf"(?m)^\s*#?\s*{re.escape(key)}=.*$"
    text = re.sub(pattern, "", text)
    text = text.rstrip() + f"\n{key}={value}\n"
text = re.sub(r"(?m)^\s*GRUB_BACKGROUND=", "#GRUB_BACKGROUND=", text)
path.write_text(text)
PY

# Give the "Advanced options" submenu and the UEFI firmware entry their own
# theme plates, exactly as the dual-boot installer does.
python - "$linux_stage" "$uefi_stage" <<'PY'
from pathlib import Path
import sys
linux = Path(sys.argv[1])
uefi = Path(sys.argv[2])

text = linux.read_text()
class_line = 'CLASS="--class gnu-linux --class gnu --class os"'
submenu_class = 'SUBMENU_CLASS="--class gnu-linux-adv"'
if submenu_class not in text:
    if class_line not in text:
        raise SystemExit("cannot locate GRUB CLASS definition in 10_linux")
    text = text.replace(class_line, class_line + "\n" + submenu_class, 1)
old = "echo \"submenu '$(gettext_printf \"Advanced options for %s\" \"${OS}\" | grub_quote)' \\$menuentry_id_option 'gnulinux-advanced-$boot_device_id' {\""
new = "echo \"submenu '$(gettext_printf \"Advanced options for %s\" \"${OS}\" | grub_quote)' ${SUBMENU_CLASS} \\$menuentry_id_option 'gnulinux-advanced-$boot_device_id' {\""
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("cannot locate Advanced options submenu in 10_linux")
linux.write_text(text)

text = uefi.read_text()
old = "menuentry '$LABEL' \\$menuentry_id_option 'uefi-firmware' {"
new = "menuentry '$LABEL' --class efi \\$menuentry_id_option 'uefi-firmware' {"
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("cannot locate firmware menuentry in 30_uefi-firmware")
uefi.write_text(text)
PY

mv -fT -- "$default_stage" "$DEFAULT_GRUB"
default_stage=""
mv -fT -- "$linux_stage" /etc/grub.d/10_linux
linux_stage=""
mv -fT -- "$uefi_stage" /etc/grub.d/30_uefi-firmware
uefi_stage=""

atomic_install "$SCRIPT_DIR/sessions/09_wintux_sessions" "$GRUBD_SESSIONS" 755
atomic_install "$SCRIPT_DIR/sessions/wintux-session-apply" "$APPLY_BIN" 755
atomic_install "$SCRIPT_DIR/sessions/sddm-10-wintux-session.conf" "$SDDM_DROPIN" 644
systemctl daemon-reload

candidate=$(mktemp /boot/grub/.wintux-grub.cfg.XXXXXXXX)
chmod 600 "$candidate"
validate_grub_inputs
grub-mkconfig -o "$candidate"
grub-script-check "$candidate"
grep -q '^menuentry ' "$candidate" || fail "generated configuration has no top-level menu entry"
grep -q "^menuentry 'KDE Plasma' --class plasma " "$candidate" || fail "generated configuration has no KDE Plasma entry"
grep -q "^menuentry 'Sway' --class sway " "$candidate" || fail "generated configuration has no Sway entry"
grep -q 'systemd.setenv=WINTUX_SESSION=plasma' "$candidate" || fail "the KDE Plasma entry does not carry its session marker"
grep -q 'systemd.setenv=WINTUX_SESSION=sway' "$candidate" || fail "the Sway entry does not carry its session marker"
# 00_header writes  set theme=($root)<path relative to the root of the
# filesystem holding it>, so strip the device prefix and compare the tail.
effective_theme=$(python - "$candidate" <<'PY'
from pathlib import Path
import re, sys
value = ""
for line in Path(sys.argv[1]).read_text().splitlines():
    match = re.match(r"^\s*set\s+theme=(.*?)\s*$", line)
    if match:
        value = match.group(1).strip().strip("\"'")
value = re.sub(r"^\([^)]*\)", "", value)
print(value)
PY
)
[[ $effective_theme == */grub/themes/wintux-sessions/theme.txt ]] || \
  fail "generated configuration does not select the wintux-sessions theme: ${effective_theme:-none}"
chown root:root "$candidate"
mv -fT -- "$candidate" "$GRUB_CFG"
candidate=""

install_complete=1
[[ -n $theme_hold ]] && rm -rf -- "$theme_hold"
theme_hold=""
trap - EXIT INT TERM
printf 'WinTux session chooser installed successfully.\n'
printf 'Backup: %s\n' "$backup_dir"
printf 'Menu order: KDE Plasma, Sway, EndeavourOS (stock), Advanced options, UEFI firmware.\n'
printf 'Reboot was NOT performed.\n'
