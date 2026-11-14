# Multi-DE session isolation and non-destructive user/first-run provisioning:
# - Eval: every systemd user service wanted by graphical-session(-pre).target
#   (including optional units like omarchy-tailscale-receive) must carry
#   ConditionEnvironment=XDG_SESSION_DESKTOP=Hyprland so GNOME/KDE sessions
#   never start Omarchy daemons; the display-manager entry labels the session
#   "Omarchy (Hyprland)".
# - Package: omarchy-startup cursor theme carries an index.theme fallback so
#   Hyprland cold-starts do not dereference NULL before ~/.icons/default exists.
# - Sandbox execution: default-keyring.sh, xcompose.sh, theme.sh,
#   first-run/gnome-theme.sh, first-run/enable-user-units.sh, and
#   bin/omarchy-provision-user preserve existing GNOME/Home Manager state.
{
  self,
  pkgs,
  system,
  ...
}:
let
  inherit (pkgs) lib;
  omarchyPkg = self.packages.${system}.omarchy;
  demoWithTailscale = (
    self.nixosConfigurations.demo.extendModules {
      modules = [ { services.tailscale.enable = true; } ];
    }
  ).config;

  graphicalUserServices = lib.filterAttrs (
    _: svc:
    lib.any (t: t == "graphical-session.target" || t == "graphical-session-pre.target") (
      svc.wantedBy or [ ]
    )
  ) demoWithTailscale.systemd.user.services;

  unscopedUserServices = lib.attrNames (
    lib.filterAttrs (
      _: svc: (svc.unitConfig.ConditionEnvironment or null) != "XDG_SESSION_DESKTOP=Hyprland"
    ) graphicalUserServices
  );

  sessionPkg = lib.findFirst (
    p: builtins.elem "hyprland-uwsm" (p.providedSessions or [ ])
  ) null demoWithTailscale.services.displayManager.sessionPackages;
in
assert
  unscopedUserServices == [ ]
  || throw "omarchy-multi-de: graphical user services missing ConditionEnvironment=XDG_SESSION_DESKTOP=Hyprland: ${toString unscopedUserServices}";
assert
  (lib.length (lib.attrNames graphicalUserServices) >= 9)
  || throw "omarchy-multi-de: expected >=9 graphical user services, got ${toString (lib.attrNames graphicalUserServices)}";
assert
  sessionPkg != null
  || throw "omarchy-multi-de: hyprland-uwsm missing from displayManager.sessionPackages";
pkgs.runCommand "omarchy-multi-de-check" { } ''
  set -euo pipefail
  fail() { echo "FAIL: $*" >&2; exit 1; }

  ROOT=${omarchyPkg}/share/omarchy
  SH=${pkgs.runtimeShell}

  mkstub() {
    local dst=$1
    shift
    printf '#!%s\n%s\n' "$SH" "$*" >"$dst"
    chmod +x "$dst"
  }

  # 1. Session desktop entry + cold-start cursor index.theme fallback.
  session_file=${sessionPkg}/share/wayland-sessions/hyprland-uwsm.desktop
  grep -qx 'Name=Omarchy (Hyprland)' "$session_file" || fail "hyprland-uwsm.desktop missing Name=Omarchy (Hyprland)"
  grep -qx 'DesktopNames=Hyprland' "$session_file" || fail "hyprland-uwsm.desktop missing DesktopNames=Hyprland"

  cursor_index=$ROOT/default/hypr/cursors/omarchy-startup/index.theme
  [[ -f $cursor_index ]] || fail "omarchy-startup/index.theme missing"
  grep -qx 'Inherits=default' "$cursor_index" || fail "omarchy-startup/index.theme missing Inherits=default"

  # 2. default-keyring.sh: preserves GNOME login.keyring; seeds empty HOME.
  H=$TMPDIR/keyring-gnome
  mkdir -p "$H/.local/share/keyrings"
  printf 'gnome-secrets' >"$H/.local/share/keyrings/login.keyring"
  HOME="$H" bash -euo pipefail "$ROOT/install/user/default-keyring.sh"
  [[ ! -e $H/.local/share/keyrings/default ]] || fail "default-keyring.sh wrote default over existing login.keyring"
  [[ ! -e $H/.local/share/keyrings/Default_keyring.keyring ]] || fail "default-keyring.sh created Default_keyring alongside login.keyring"

  H=$TMPDIR/keyring-empty
  mkdir -p "$H"
  HOME="$H" bash -euo pipefail "$ROOT/install/user/default-keyring.sh"
  [[ -f $H/.local/share/keyrings/Default_keyring.keyring && $(cat "$H/.local/share/keyrings/default") == Default_keyring ]] ||
    fail "default-keyring.sh did not initialize an empty keyring dir"

  # 3. xcompose.sh: preserves existing file/symlink; uses /run/current-system on fresh HOME.
  H=$TMPDIR/xcompose-existing
  mkdir -p "$H"
  printf '<Multi_key> <a> : "custom"\n' >"$H/.XCompose"
  HOME="$H" OMARCHY_USER_NAME="Test" OMARCHY_USER_EMAIL="t@example.com" \
    bash -euo pipefail "$ROOT/install/user/xcompose.sh"
  [[ $(cat "$H/.XCompose") == '<Multi_key> <a> : "custom"' ]] || fail "xcompose.sh overwrote existing ~/.XCompose"

  H=$TMPDIR/xcompose-fresh
  mkdir -p "$H"
  HOME="$H" OMARCHY_USER_NAME="Test" OMARCHY_USER_EMAIL="t@example.com" \
    bash -euo pipefail "$ROOT/install/user/xcompose.sh"
  grep -qx 'include "/run/current-system/sw/share/omarchy/default/xcompose"' "$H/.XCompose" ||
    fail "xcompose.sh missing stable /run/current-system include"
  ! grep -qE '/usr/share|/nix/store' "$H/.XCompose" || fail "xcompose.sh leaked Arch or store path"

  # 4. theme.sh + first-run/gnome-theme.sh: DBUS_SESSION_BUS_ADDRESS cleared during
  #    initial provisioning; gnome-theme.sh only writes unset dconf keys.
  STUB=$TMPDIR/stub
  mkdir -p "$STUB"
  export LOG=$TMPDIR/calls.log

  mkstub "$STUB/omarchy-theme-set" 'printf "theme-set dbus=%s arg=%s\n" "''${DBUS_SESSION_BUS_ADDRESS-<unset>}" "$*" >>"$LOG"'
  mkstub "$STUB/omarchy-theme-set-pi" 'exit 0'
  mkstub "$STUB/omarchy-theme-set-fcitx5" 'exit 0'
  mkstub "$STUB/dconf" '
    case "$2" in
      /org/gnome/desktop/interface/gtk-theme) echo "'"'"'Adwaita'"'"'" ;;
      /org/gnome/desktop/interface/icon-theme) echo "'"'"'Adwaita'"'"'" ;;
    esac
  '
  mkstub "$STUB/gsettings" 'printf "gsettings %s\n" "$*" >>"$LOG"'

  : >"$LOG"
  H=$TMPDIR/theme-home
  mkdir -p "$H"
  HOME="$H" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" PATH="$STUB:$PATH" \
    bash -euo pipefail "$ROOT/install/user/theme.sh"
  grep -qx 'theme-set dbus= arg=Tokyo Night' "$LOG" ||
    fail "theme.sh did not clear DBUS_SESSION_BUS_ADDRESS for initial omarchy-theme-set"

  : >"$LOG"
  PATH="$STUB:$PATH" bash -euo pipefail "$ROOT/install/user/first-run/gnome-theme.sh"
  [[ $(cat "$LOG") == 'gsettings set org.gnome.desktop.interface color-scheme prefer-dark' ]] ||
    fail "gnome-theme.sh overwrote populated dconf keys: $(cat "$LOG")"

  # 5. first-run/enable-user-units.sh: starts loaded units, skips unloaded ones,
  #    never runs `systemctl --user enable`.
  mkstub "$STUB/omarchy-input-method" 'exit 0'
  mkstub "$STUB/omarchy-hook-install" 'printf "hook %s\n" "$*" >>"$LOG"'
  mkstub "$STUB/systemctl" '
    printf "systemctl %s\n" "$*" >>"$LOG"
    if [[ "$*" == *"show -p LoadState --value "* ]]; then
      case "''${!#}" in
        bt-agent.service|owed.service) echo loaded ;;
        *) echo not-found ;;
      esac
    fi
  '

  : >"$LOG"
  PATH="$STUB:$PATH" bash -euo pipefail "$ROOT/install/user/first-run/enable-user-units.sh"
  ! grep -q 'enable' "$LOG" || fail "enable-user-units.sh ran systemctl enable"
  grep -qx 'systemctl --user start bt-agent.service' "$LOG" || fail "enable-user-units.sh did not start loaded bt-agent"
  grep -qx 'systemctl --user start owed.service' "$LOG" || fail "enable-user-units.sh did not start loaded owed"
  ! grep -q 'start omarchy-fcitx5.service' "$LOG" || fail "enable-user-units.sh started unloaded omarchy-fcitx5"
  grep -qx 'hook theme-set /run/current-system/sw/share/owe/10-owe-sync' "$LOG" ||
    fail "enable-user-units.sh did not wire OWE hook on stable system-profile path"

  # 6. bin/omarchy-provision-user: HM skill links, user-dirs, and MIME defaults.
  #    omarchy-provision-user prepends $OMARCHY_PATH/bin to PATH, so stage a
  #    symlinked OMARCHY_PATH tree where omarchy-pkg-present and
  #    omarchy-refresh-applications are deterministic test stubs.
  PROV_ROOT=$TMPDIR/omarchy-root
  cp -rs "$ROOT" "$PROV_ROOT"
  chmod -R u+w "$PROV_ROOT/bin"
  rm -f "$PROV_ROOT/bin/omarchy-pkg-present" "$PROV_ROOT/bin/omarchy-refresh-applications"

  INSTALL_STUB=$TMPDIR/install-stub
  mkdir -p "$INSTALL_STUB/user"
  printf '# stub user/all.sh\n' >"$INSTALL_STUB/user/all.sh"

  mkstub "$PROV_ROOT/bin/omarchy-refresh-applications" 'exit 0'
  mkstub "$PROV_ROOT/bin/omarchy-pkg-present" '[[ ''${CHROMIUM_PRESENT:-1} == 1 ]]'
  mkstub "$STUB/xdg-user-dirs-update" 'printf "user-dir %s=%s\n" "$2" "$3" >>"$LOG"'
  mkstub "$STUB/xdg-settings" 'printf "xdg-settings %s\n" "$*" >>"$LOG"'
  mkstub "$STUB/xdg-mime" '
    if [[ "$1 $2" == "query default" ]]; then
      printf "%s" "''${ACTIVE_MAILTO:-}"
      exit 0
    fi
    printf "xdg-mime %s\n" "$*" >>"$LOG"
  '

  run_provision() {
    : >"$LOG"
    env HOME="$H" OMARCHY_PATH="$PROV_ROOT" OMARCHY_INSTALL="$INSTALL_STUB" \
      PATH="$PROV_ROOT/bin:$STUB:$PATH" "$@" \
      bash -euo pipefail "$PROV_ROOT/bin/omarchy-provision-user" --force >/dev/null
  }

  # 6a. Fresh HOME + chromium present -> sets chromium.desktop + HEY.desktop, links skills (not omarchy-app).
  H=$TMPDIR/prov-fresh
  mkdir -p "$H/Desktop" "$H/Templates"
  run_provision CHROMIUM_PRESENT=1 ACTIVE_MAILTO=""
  grep -qx 'xdg-settings set default-web-browser chromium.desktop' "$LOG" || fail "fresh HOME missed default-web-browser"
  grep -qx 'xdg-mime default HEY.desktop x-scheme-handler/mailto' "$LOG" || fail "fresh HOME missed HEY mailto"
  [[ ! -d $H/Desktop && ! -d $H/Templates ]] || fail "fresh HOME did not collapse empty Desktop/Templates"
  [[ ! -e $H/.gemini/config/skills/omarchy-app ]] || fail "provision-user linked retired omarchy-app skill"
  [[ -L $H/.gemini/config/skills/omarchy ]] || fail "provision-user did not link omarchy skill"

  # 6b. Populated multi-DE + HM HOME -> preserves HM skill symlinks, configured Desktop, and ~/.config/mimeapps.list.
  H=$TMPDIR/prov-hm
  mkdir -p "$H/.gemini/config/skills" "$H/.hermes/profiles/default/skills" "$H/.config" "$H/Desktop"
  ln -s /nix/store/00000000000000000000000000000000-home-manager-files/.gemini/config/skills/omarchy \
    "$H/.gemini/config/skills/omarchy"
  ln -s /nix/store/00000000000000000000000000000000-home-manager-files/.hermes/skills/omarchy \
    "$H/.hermes/profiles/default/skills/omarchy"
  printf 'XDG_DESKTOP_DIR="$HOME/Desktop"\n' >"$H/.config/user-dirs.dirs"
  printf '[Default Applications]\ntext/html=firefox.desktop\nx-scheme-handler/mailto=org.gnome.Evolution.desktop\n' \
    >"$H/.config/mimeapps.list"
  run_provision CHROMIUM_PRESENT=1 ACTIVE_MAILTO=""
  [[ $(readlink "$H/.gemini/config/skills/omarchy") == /nix/store/*-home-manager-files/* ]] ||
    fail "provision-user overwrote HM skill link in ~/.gemini"
  [[ $(readlink "$H/.hermes/profiles/default/skills/omarchy") == /nix/store/*-home-manager-files/* ]] ||
    fail "provision-user overwrote HM skill link in ~/.hermes/profiles"
  [[ -d $H/Desktop ]] || fail "provision-user deleted pre-configured ~/Desktop"
  ! grep -q 'user-dir DESKTOP=' "$LOG" || fail "provision-user overwrote XDG_DESKTOP_DIR"
  ! grep -qE '^xdg-(settings|mime) ' "$LOG" || fail "provision-user overwrote ~/.config/mimeapps.list defaults: $(cat "$LOG")"

  # 6c. Legacy ~/.local/share/applications/mimeapps.list -> respected too.
  H=$TMPDIR/prov-legacy-mime
  mkdir -p "$H/.local/share/applications"
  printf '[Default Applications]\nx-scheme-handler/http=firefox.desktop\nx-scheme-handler/mailto=thunderbird.desktop\n' \
    >"$H/.local/share/applications/mimeapps.list"
  run_provision CHROMIUM_PRESENT=1 ACTIVE_MAILTO=""
  ! grep -qE '^xdg-(settings|mime) ' "$LOG" || fail "provision-user ignored legacy ~/.local/share/applications/mimeapps.list"

  # 6d. Store-symlinked ~/.config/mimeapps.list -> skipped cleanly.
  H=$TMPDIR/prov-store-mime
  mkdir -p "$H/.config"
  ln -s /nix/store/00000000000000000000000000000000-home-manager-files/.config/mimeapps.list "$H/.config/mimeapps.list"
  run_provision CHROMIUM_PRESENT=1 ACTIVE_MAILTO=""
  ! grep -qE '^xdg-(settings|mime) ' "$LOG" || fail "provision-user wrote through store-symlinked mimeapps.list"

  # 6e. Excluded chromium + system mailto handler -> neither default forced.
  H=$TMPDIR/prov-excluded
  mkdir -p "$H"
  run_provision CHROMIUM_PRESENT=0 ACTIVE_MAILTO="thunderbird.desktop"
  ! grep -qE '^xdg-(settings|mime) ' "$LOG" || fail "provision-user set chromium or HEY despite excluded chromium + active mailto"

  touch $out
''
