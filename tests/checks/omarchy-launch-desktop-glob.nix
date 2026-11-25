# Browser and webapp launchers read .desktop entries via XDG_DATA_DIRS.
# When XDG_DATA_DIRS is unset in non-login contexts, the fallback must
# include NixOS profile share dirs rather than only /usr/local/share:/usr/share.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  nixosFallback = "XDG_DATA_DIRS:-$HOME/.nix-profile/share:/run/current-system/sw/share:/usr/local/share:/usr/share";
  archFallback = "XDG_DATA_DIRS:-/usr/local/share:/usr/share";
in
pkgs.runCommand "omarchy-launch-desktop-glob" { } ''
  for script in \
    ${omarchyPkg}/share/omarchy/bin/omarchy-launch-webapp \
    ${omarchyPkg}/share/omarchy/bin/omarchy-launch-browser \
    ${omarchyPkg}/share/omarchy/bin/omarchy-cmd-default-browser; do
    grep -Fq '${nixosFallback}' "$script" || {
      echo "$(basename "$script") missing NixOS XDG_DATA_DIRS fallback" >&2
      exit 1
    }
    grep -Fq '${archFallback}' "$script" && {
      echo "$(basename "$script") still has the Arch-only XDG_DATA_DIRS fallback" >&2
      exit 1
    }
  done
  touch $out
''
