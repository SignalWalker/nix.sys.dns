{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  dlib = config.lib.services.nameserver;
  ns = config.services.nameserver;
  be = ns.backend;
  bind = ns.generators.bind;
in {
  options.services.nameserver = {
    backend = {
      type = mkOption {type = types.nullOr (types.enum ["bind"]);};
      bind = {
        package = (mkPackageOption pkgs "bind" {}) // {default = config.services.bind.package;};
      };
    };
    generators.bind = mkOption {
      type = types.coercedTo types.bool (enable: {inherit enable;}) (types.submoduleWith {
        modules = [
          ({
            config,
            lib,
            ...
          }: {
            enable = (mkEnableOption "bind9 configuration") // {default = ns.backend == "bind";};
            rndc = {
              address = mkOption {
                type = types.str;
                default = "127.0.0.1";
                description = "Address at which named listens for rndc command-channel connections.";
              };
              port = mkOption {
                type = types.port;
                default = 953;
              };
              name = mkOption {
                type = types.str;
                default = name;
                description = "The name used to identify this key in nameserver configurations.";
              };
            };
            configFile = let
              listToNStr' = sep: list: concatMapStringsSep sep (e: "${e};") list;
              listToNStr = list: listToNStr' " " list;
              zoneStr = concatMapStringsSep "\n" (zoneName: let
                zone = ns.zones.${zoneName};
              in ''
                zone "${zone.origin}" {
                	type ${
                  if zone.isPrimary
                  then "primary"
                  else "secondary"
                };
                	file "${zone.file}";
                	${
                  if zone.isPrimary
                  then ''
                    allow-transfer {
                    	${listToNStr' "\n" zone.secondaries}
                    };
                  ''
                  else ''
                    primaries {
                    	${listToNStr' "\n" zone.primaries}
                    };
                  ''
                }
                	allow-query { any; };
                };
              '') (attrNames ns.zones);
            in
              mkOption {
                type = types.path;
                default = pkgs.writeText "named.conf" ''
                  controls {
                  	inet 127.0.0.1 allow { localhost; } keys {"${bind.rndc.key}"};
                  };

                  acl cachenetworks { ${listToNStr ns.networks.cache} };
                  acl badnetworks   { ${listToNStr ns.networks.block} };

                  options {

                  };

                  ${zoneStr}
                '';
                readOnly = true;
                description = "Configuration file read by named at runtime. Automatically generated.";
              };
          })
        ];
      });
      default = {};
      description = "Generate DNS configuration for BIND9.";
    };
  };
  disabledModules = [];
  imports = [];
  config = lib.mkMerge [
    (lib.mkIf bind.enable {
      services.bind = {
        blockedNetworks = ns.networks.blocked;
        cacheNetworks = ns.networks.cache;
        forwarders = ns.networks.forward;
        inherit (ns) forward;
        ipv4Only = lib.mkDefault (ns.ipv6.interfaces == []);
        listenOn = ns.ipv4.interfaces;
        listenOnIpv6 = ns.ipv6.interfaces;
        zones =
          std.mapAttrs' (key: zone: {
            name = zone.origin;
            value = {
              inherit (zone) file;
              name = zone.origin;
              master = zone.primaries != [];
              masters = zone.primaries;
              slaves = zone.secondaries;
            };
          })
          ns.zones;
      };
    })
    (lib.mkIf (be.type == "bind") {
      assertions = [
        {
          assertion = bind.enable;
          message = "must enable `services.nameserver.generators.bind` to use `services.nameserver.backend.type = \"bind\"`";
        }
        {
          assertion = !services.bind.enable;
          message = "must disable `services.bind` to use `services.nameserver.backend.type = \"bind\"`";
        }
      ];
      services.nameserver.generators.bind.enable = lib.mkForce true;
      services.bind.enable = lib.mkForce false; # nixpkg's bind module unavoidably does some extra stuff, so we're just gonna do stuff manually here
      # user account & group are set up in the main part of the module
      systemd.services.${be.systemd.serviceName} = {
        preStart = ''
          if ![[ -f "${bind.rndc.key}" ]]; then
          	# rndc key doesn't exist; generate it
          	if ! ${bind.package.out}/sbin/rndc-confgen -c '${bind.rndc.key}' -A hmac-${bind.rndc.algorithm} -u '${be.user}' -a -q; then
          		echo "Failed to create '${bind.rndc.key}'; exitting..."
          		exit 1
          	fi
          fi
        '';
        serviceConfig = {
          ExecStart = assert ports != []; "${be.bind.package.out}/sbin/named -f -u ${be.user}";
          ExecReload = "";
          ExecStop = "";
        };
      };
    })
  ];
  meta = {};
}
