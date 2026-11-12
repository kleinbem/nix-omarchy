{ pkgs, ... }:

{
  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "omarchy-host";
  networking.networkmanager.enable = true;

  # Enable Omarchy Desktop (Hyprland + Quickshell)
  omarchy = {
    enable = true;
    theme = "vantablack";
  };

  # Define your user account
  users.users.user = {
    isNormalUser = true;
    description = "User";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "input"
    ];
  };

  # Seed per-user Omarchy configuration
  home-manager.users.user.omarchy.enable = true;

  system.stateVersion = "26.05";
}
