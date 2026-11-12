# Omarchy on NixOS Starter Template

A clean, reproducible starting point for running the Omarchy Wayland desktop on NixOS.

## Quick Start

1. Initialize into a directory:
   ```bash
   nix flake init -t github:kleinbem/nix-omarchy
   ```
2. Copy your machine's hardware configuration:
   ```bash
   nixos-generate-config --show-hardware-config > hardware-configuration.nix
   ```
3. Update the username and hostname in `configuration.nix` and `flake.nix`.
4. Rebuild and switch:
   ```bash
   sudo nixos-rebuild switch --flake .#my-host
   ```
