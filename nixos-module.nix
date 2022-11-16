{
  self,
  nixpkgs,
  ...
}: {
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  dlib = config.lib.services.nameserver;
  ns = config.services.nameserver;
in {
  options.services.nameserver = with lib; {
    networks = {
      block = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      cache = mkOption {
        type = types.listOf types.str;
        default = ["127.0.0.1/24"];
      };
      forward = mkOption {
        type = types.listOf types.str;
        default = config.networking.nameservers;
      };
    };
    ipv4 = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = ["any"];
      };
    };
    ipv6 = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = ["any"];
      };
    };
    forward = mkOption {
      type = types.enum ["first" "only"];
      default = "first";
    };
    zones = mkOption {
      type = types.attrsOf dlib.types.zone;
      default = {};
    };
  };
  disabledModules = [];
  imports = [
    ./src/lib.nix
    ./src/bind.nix
    ./src/backend.nix
  ];
  config = {
  };
  meta = {};
}
