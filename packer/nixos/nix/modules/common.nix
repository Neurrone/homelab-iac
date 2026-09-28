{ lib, pkgs, ... }:
{
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200n8" ];

  networking.hostName = "nixos-template";
  networking.useDHCP = lib.mkDefault true;

  services.qemuGuest.enable = true;
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    curl
    git
  ];

  time.timeZone = lib.mkDefault "UTC";

  system.stateVersion = "25.11";
}
