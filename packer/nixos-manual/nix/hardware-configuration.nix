{ ... }:
{
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "sr_mod"
    "virtio_blk"
    "virtio_pci"
    "virtio_scsi"
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  swapDevices = [ ];
}
