{ lib, ... }:
let
  bootstrapSecretsPath = ../generated/bootstrap-secrets.nix;
  bootstrapSecretsModule =
    if builtins.pathExists bootstrapSecretsPath then
      import bootstrapSecretsPath
    else
      ({ ... }: {
        assertions = [{
          assertion = false;
          message = "Missing generated/bootstrap-secrets.nix (Packer shell-local generates this before running nixos-anywhere).";
        }];
      });
in
{
  imports = [ bootstrapSecretsModule ];

  # Keep bootstrap access minimal and temporary. Packer switches to the final config
  # before sanitizing and powering off the template.
  users.mutableUsers = false;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = true;
  };
}
