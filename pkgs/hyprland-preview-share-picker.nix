# Upstream "hyprland-preview-share-picker": an alternative xdg-desktop-portal
# screencopy picker for Hyprland with live window/monitor previews. Written in
# Rust (edition 2024) with a GTK4 + gtk4-layer-shell UI.
#
# It is NOT a portal backend itself -- it ships no .portal file and no D-Bus
# service. xdg-desktop-portal-hyprland invokes it as its
# `custom_picker_binary` (configured in xdph.conf under [screencopy]). So the
# module only needs the binary on PATH plus the xdg-desktop-portal-hyprland
# runtime dep; no portal/dbus registration is required on our side.
#
# The upstream PKGBUILD also runs the binary's `schema` subcommand and installs
# the generated schema.json; we deliberately do NOT (see the NOTE below).
#
# Source includes a git submodule (hyprwm/hyprland-protocols) under lib/, used
# by the wayland-scanner codegen, so fetchSubmodules is required.
{
  lib,
  glib,
  gtk4,
  gtk4-layer-shell,
  pkg-config,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hyprland-preview-share-picker";
  # Workaround: our nixpkgs input still has 0.2.1. Drop this file for
  # pkgs.hyprland-preview-share-picker once it has NixOS/nixpkgs#582643.
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "WhySoBad";
    repo = "hyprland-preview-share-picker";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-0yn7YG18SC6+h3vkJNDUda/esmBl6U1tu1LHIIXSknc=";
  };

  cargoHash = "sha256-4nd0X6Ii6pbpQgzFCw2yXhl2+C5FyqDsHtbzKNpGW5o=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    glib
    gtk4
    gtk4-layer-shell
  ];

  strictDeps = true;

  # build.rs runs `git describe`/`git log` for an embedded version string. The
  # fetched source has no .git, so it degrades to "unknown" with a benign
  # cargo warning; this matches upstream package.nix behavior.
  #
  # NOTE: upstream's PKGBUILD also installs a generated share/schema.json by
  # running `hyprland-preview-share-picker schema`. That subcommand still
  # initializes GTK4, which segfaults headless in the sandbox, so we omit it.
  # The schema is only a config reference for IDE completion; the picker works
  # without a pre-installed schema.json (config is read from
  # $XDG_CONFIG_HOME/hyprland-preview-share-picker/config.yaml at runtime).

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Alternative share picker for Hyprland with window and monitor previews";
    homepage = "https://github.com/WhySoBad/hyprland-preview-share-picker";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprland-preview-share-picker";
  };
})
