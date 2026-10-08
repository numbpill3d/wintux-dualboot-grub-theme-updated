#!/usr/bin/env bash
# Undo install-sessions-endeavouros.sh.
#
# Restores /etc/default/grub, /etc/grub.d/10_linux, /etc/grub.d/30_uefi-firmware
# and the previous theme directory from a backup, removes the files the
# installer added (09_wintux_sessions, wintux-session-apply, the sddm drop-in)
# unless they existed beforehand, and regenerates grub.cfg.
#
#   sudo ./rollback-sessions-endeavouros.sh --apply [backup-directory]
set -Eeuo pipefail
readonly PATH=/usr/bin
export PATH

readonly BACKUP_ROOT="/var/backups/wintux-sessions"
readonly DEFAULT_GRUB="/etc/default/grub"
readonly GRUB_CFG="/boot/grub/grub.cfg"
readonly THEME_DEST="/boot/grub/themes/wintux-sessions"

readonly ADDED_FILES=(
  "09_wintux_sessions:/etc/grub.d/09_wintux_sessions:755"
  "wintux-session-apply:/usr/local/bin/wintux-session-apply:755"
  "sddm-dropin.conf:/etc/systemd/system/sddm.service.d/10-wintux-session.conf:644"
)

candidate=""
safety_dir=""
theme_stage=""
theme_hold=""
restore_started=0
rollback_complete=0
theme_was_absent=0

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

validate_secure_theme_tree() {
  local path=$1 unsafe
  unsafe=$(find "$path" \( -type l -o \( ! -type d -a ! -type f \) -o ! -user root -o -perm /022 \) -print -quit)
  [[ -z $unsafe ]] || fail "theme contains an unsafe path: $unsafe"
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

# Put each added file back the way <dir> recorded it.
apply_added_files_from() {
  local dir=$1 entry name destination mode
  for entry in "${ADDED_FILES[@]}"; do
    IFS=: read -r name destination mode <<<"$entry"
    if [[ -f $dir/$name.previous ]]; then
      atomic_install "$dir/$name.previous" "$destination" "$mode" || true
    elif [[ -f $dir/$name.absent ]]; then
      rm -f -- "$destination" || true
    fi
  done
}

snapshot_added_files_to() {
  local dir=$1 entry name destination mode
  for entry in "${ADDED_FILES[@]}"; do
    IFS=: read -r name destination mode <<<"$entry"
    if [[ -f $destination && ! -L $destination ]]; then
      cp -a -- "$destination" "$dir/$name.previous"
    else
      : > "$dir/$name.absent"
      chmod 600 "$dir/$name.absent"
    fi
  done
}

restore_pre_rollback_on_error() {
  local status=$?
  trap - EXIT INT TERM
  if (( status != 0 && restore_started == 1 && rollback_complete == 0 )) && [[ -n $safety_dir ]]; then
    printf 'Rollback failed; restoring the pre-rollback state from %s\n' "$safety_dir" >&2
    atomic_install "$safety_dir/grub.default" "$DEFAULT_GRUB" 644 || true
    atomic_install "$safety_dir/10_linux" /etc/grub.d/10_linux 755 || true
    atomic_install "$safety_dir/30_uefi-firmware" /etc/grub.d/30_uefi-firmware 755 || true
    atomic_install "$safety_dir/grub.cfg" "$GRUB_CFG" 600 || true
    apply_added_files_from "$safety_dir"
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [[ -n $theme_hold && -d $theme_hold/original ]]; then
      rm -rf -- "$THEME_DEST"
      mv -- "$theme_hold/original" "$THEME_DEST" || true
    elif (( theme_was_absent == 1 )); then
      rm -rf -- "$THEME_DEST"
    fi
  fi
  [[ -n $candidate ]] && rm -f -- "$candidate"
  [[ -n $theme_stage ]] && rm -rf -- "$theme_stage"
  [[ -n $theme_hold ]] && rm -rf -- "$theme_hold"
  exit "$status"
}
trap restore_pre_rollback_on_error EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ ${EUID} -eq 0 ]] || fail "run with sudo"
[[ ${1:-} == "--apply" ]] || fail "refusing to change GRUB without the --apply flag"
(( $# <= 2 )) || fail "usage: sudo $0 --apply [backup-directory]"
for command in grub-mkconfig grub-script-check flock install mktemp realpath stat find systemctl; do
  command -v "$command" >/dev/null || fail "$command is missing"
done
for file in "$DEFAULT_GRUB" /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware "$GRUB_CFG"; do
  validate_secure_file "$file"
done
validate_secure_directory /etc
validate_secure_directory /etc/default
validate_secure_directory /etc/grub.d
validate_secure_directory /run
validate_secure_directory /run/lock
validate_secure_directory /boot
validate_secure_directory /boot/grub
validate_grub_inputs

exec 9>/run/lock/wintux-sessions.lock
flock -n 9 || fail "another WinTux operation is already running"
prepare_secure_directory /boot/grub/themes 755
validate_secure_directory /var
validate_secure_directory /var/backups
validate_secure_directory "$BACKUP_ROOT"

if [[ -n ${2:-} ]]; then
  backup_dir=$(realpath -e -- "$2")
else
  [[ -f $BACKUP_ROOT/LATEST && ! -L $BACKUP_ROOT/LATEST ]] || fail "no safe recorded WinTux backup"
  backup_dir=$(realpath -e -- "$(< "$BACKUP_ROOT/LATEST")")
fi
backup_root_real=$(realpath -e -- "$BACKUP_ROOT")
[[ $(dirname -- "$backup_dir") == "$backup_root_real" ]] || fail "backup directory must be a direct child of $BACKUP_ROOT"
[[ -d $backup_dir && ! -L $backup_dir ]] || fail "backup directory is unsafe: $backup_dir"
[[ $(stat -c %u -- "$backup_dir") == 0 ]] || fail "backup directory is not root-owned: $backup_dir"
mode=$(stat -c %a -- "$backup_dir")
permissions=$((8#$mode))
(( (permissions & 8#022) == 0 )) || fail "backup directory is group/world writable: $backup_dir"
for file in grub.default 10_linux 30_uefi-firmware grub.cfg; do
  path="$backup_dir/$file"
  [[ -f $path && ! -L $path ]] || fail "backup is incomplete or unsafe: $path"
  [[ $(stat -c %u -- "$path") == 0 ]] || fail "backup file is not root-owned: $path"
  file_mode=$(stat -c %a -- "$path")
  file_permissions=$((8#$file_mode))
  (( (file_permissions & 8#022) == 0 )) || fail "backup file is group/world writable: $path"
done
for entry in "${ADDED_FILES[@]}"; do
  IFS=: read -r name destination mode <<<"$entry"
  [[ -f $backup_dir/$name.previous || -f $backup_dir/$name.absent ]] || \
    fail "backup does not record the prior state of $destination"
done
if [[ -e $backup_dir/theme.previous || -L $backup_dir/theme.previous ]]; then
  [[ -d $backup_dir/theme.previous && ! -L $backup_dir/theme.previous ]] || fail "previous theme backup is unsafe"
  validate_secure_theme_tree "$backup_dir/theme.previous"
fi

# Preserve the current state so a failed rollback can itself be rolled back.
safety_dir=$(mktemp -d "$BACKUP_ROOT/pre-rollback-XXXXXXXX")
chmod 700 "$safety_dir"
cp -a -- "$DEFAULT_GRUB" "$safety_dir/grub.default"
cp -a -- /etc/grub.d/10_linux "$safety_dir/10_linux"
cp -a -- /etc/grub.d/30_uefi-firmware "$safety_dir/30_uefi-firmware"
cp -a -- "$GRUB_CFG" "$safety_dir/grub.cfg"
snapshot_added_files_to "$safety_dir"

restore_started=1
atomic_install "$backup_dir/grub.default" "$DEFAULT_GRUB" 644
atomic_install "$backup_dir/10_linux" /etc/grub.d/10_linux 755
atomic_install "$backup_dir/30_uefi-firmware" /etc/grub.d/30_uefi-firmware 755
apply_added_files_from "$backup_dir"
systemctl daemon-reload

if [[ -d $backup_dir/theme.previous ]]; then
  theme_stage=$(mktemp -d "$(dirname -- "$THEME_DEST")/.wintux-rollback-stage-XXXXXXXX")
  cp -a -- "$backup_dir/theme.previous/." "$theme_stage/"
  chown -R root:root "$theme_stage"
  find "$theme_stage" -type d -exec chmod 755 {} +
  find "$theme_stage" -type f -exec chmod 644 {} +
  validate_secure_theme_tree "$theme_stage"
  if [[ -e $THEME_DEST || -L $THEME_DEST ]]; then
    [[ -d $THEME_DEST && ! -L $THEME_DEST ]] || fail "current theme destination is unsafe: $THEME_DEST"
    validate_secure_theme_tree "$THEME_DEST"
    theme_hold=$(mktemp -d "$(dirname -- "$THEME_DEST")/.wintux-rollback-hold-XXXXXXXX")
    mv -- "$THEME_DEST" "$theme_hold/original"
  else
    theme_was_absent=1
  fi
  mv -- "$theme_stage" "$THEME_DEST"
  theme_stage=""
fi

candidate=$(mktemp /boot/grub/.wintux-rollback-grub.cfg.XXXXXXXX)
chmod 600 "$candidate"
validate_grub_inputs
grub-mkconfig -o "$candidate"
grub-script-check "$candidate"
grep -q '^menuentry ' "$candidate" || fail "restored configuration has no top-level menu entry"
chown root:root "$candidate"
mv -fT -- "$candidate" "$GRUB_CFG"
candidate=""

rollback_complete=1
[[ -n $theme_hold ]] && rm -rf -- "$theme_hold"
theme_hold=""
trap - EXIT INT TERM
printf 'GRUB configuration restored from %s.\n' "$backup_dir"
printf 'Pre-rollback safety copy: %s\n' "$safety_dir"
if [[ -d $backup_dir/theme.previous ]]; then
  printf 'The previous theme directory was restored.\n'
else
  printf 'No previous theme directory was backed up; %s was left in place but is no longer selected.\n' "$THEME_DEST"
fi
