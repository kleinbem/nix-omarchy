#!/usr/bin/env bash
# Generic updater for every package here whose passthru.updateScript is
# nix-update-script: the package's own extraArgs say how it updates.
#
# Usage:  ./scripts/update-packages.sh list          # JSON [{attr,args}] for a CI matrix
#         ./scripts/update-packages.sh update <attr> [nix-update args]
#                                                    # bump, build and test one package
# Deps:   bash, jq, nix
set -euo pipefail

cd "$(dirname "$0")/.."
SYSTEM="${SYSTEM:-x86_64-linux}"

list() {
  # shellcheck disable=SC2016 # Nix, not shell
  nix eval --json ".#packages.$SYSTEM" --apply '
    ps: builtins.concatMap (n:
      if n == "default" then [ ] else
      let r = builtins.tryEval (
        let p = ps.${n}; in
        if builtins.isAttrs p && p ? updateScript && builtins.isList p.updateScript
          && builtins.match ".*/bin/nix-update" (builtins.unsafeDiscardStringContext
               (builtins.head p.updateScript)) != null
        then [ {
          attr = n;
          args = builtins.tail p.updateScript;
          tests = (p.passthru.tests or { }) != { };
          position = builtins.unsafeDiscardStringContext (p.meta.position or "");
        } ]
        else [ ]);
      in if r.success then r.value else [ ]) (builtins.attrNames ps)' |
    jq -c '.[] | .file = (.position | sub("^/nix/store/[^/]+/"; "") | sub(":[0-9]+$"; ""))' |
    while read -r entry; do
      if [[ -f "$(jq -r .file <<<"$entry")" ]]; then
        jq -c '{attr, args, tests}' <<<"$entry"
      fi
    done | jq -sc .
}

update() {
  local attr="$1" entry
  shift
  entry=$(list | jq -c --arg a "$attr" '.[] | select(.attr == $a)')
  [[ -n $entry ]] || {
    echo "no nix-update updateScript for $attr" >&2
    exit 1
  }
  local -a extra
  mapfile -t extra < <(jq -r '.args[]' <<<"$entry")
  [[ "$(jq .tests <<<"$entry")" == false ]] || extra+=(--test)
  nix run --inputs-from . nixpkgs#nix-update -- \
    --flake --system "$SYSTEM" --build "${extra[@]}" "$@" "$attr"
}

case "${1:-}" in
list) list ;;
update)
  shift
  update "${1:?attr}" "${@:2}"
  ;;
*)
  echo "usage: $0 list | update <attr>" >&2
  exit 2
  ;;
esac
