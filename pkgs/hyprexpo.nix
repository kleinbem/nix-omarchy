# hyprexpo — Exposé-style workspace and window overview Hyprland plugin
# (sandwichfarm/hyprexpo, maintained fork with Hyprland 0.56+ Lua support).
#
# MUST be built against the same Hyprland the desktop runs (plugin ABI):
# the flake calls this with hyprland = the `hyprland` flake input's package
# and the nixpkgs of that input, so headers, toolchain and linked libs line
# up with the compositor. Pin matches hyprpm.toml's 0.56.2 entry.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  lua5_4,
  hyprland,
}:

stdenv.mkDerivation {
  pname = "hyprexpo";
  version = "0.56.2-unstable-2026-10-16";

  src = fetchFromGitHub {
    owner = "sandwichfarm";
    repo = "hyprexpo";
    rev = "59bf4d378cecde9ed849e9c562306738b1583016";
    hash = "sha256-PzNImRfn91/O2OdRik6quBiOs0v/dGrnoDSKyZ/kVPQ=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  # hyprland first: its dev output provides hyprland.pc; its buildInputs
  # cover pixman, libdrm, pangocairo, libinput, udev, wayland-server, xkbcommon.
  buildInputs = [
    hyprland
    lua5_4
  ]
  ++ hyprland.buildInputs;

  doCheck = true;

  meta = {
    description = "Exposé-style workspace and window overview plugin for Hyprland";
    homepage = "https://github.com/sandwichfarm/hyprexpo";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
