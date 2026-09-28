{
  description = "NixOS template configs for Packer + nixos-anywhere on Proxmox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      mkTemplate = role: lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko/vda-ext4.nix
          ./modules/common.nix
          (if role == "bootstrap" then ./modules/bootstrap.nix else ./modules/final.nix)
        ];
      };
    in
    {
      nixosConfigurations = {
        nixos-template-bootstrap = mkTemplate "bootstrap";
        nixos-template-final = mkTemplate "final";
      };
    };
}
