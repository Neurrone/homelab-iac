{ lib, pkgs, ... }:
{
  imports = [
    ../hardware-configuration.nix
    ../state-version.nix
    ./bootstrap-secrets.nix
  ];

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
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = true;
  };

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Declaratively create the temporary user used by Packer after the first reboot.
  users.mutableUsers = false;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    curl
    git
  ];

  time.timeZone = lib.mkDefault "UTC";
}
