# nix-omarchy Justfile
# Opinionated Omarchy desktop vendored and rewired for NixOS

[group("Main")]
default:
    @just --list

[group("Linter")]
check:
    @echo "🧩 Checking nix-omarchy flake..."
    @nix flake check . --impure

[group("Linter")]
fmt:
    @nix fmt

[group("Update")]
update-upstream:
    @echo "🔄 Updating omarchy-src from upstream..."
    @nix flake lock --update-input omarchy-src
    @nix flake check . --impure
