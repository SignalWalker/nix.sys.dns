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
  submodule = mod: lib.types.submoduleWith {modules = [mod];};
  keyModule = submodule ({
    config,
    lib,
    name,
    ...
  }: {
    options = {
      file = mkOption {
        type = types.str;
        description = ''
          Path from which to read the key at runtime.
          This should be readable/writeable only by the nameserver user.
        '';
      };
      algorithm = mkOption {
        type = types.enum ["hmac-md5" "hmac-sha1" "hmac-sha224" "hmac-sha256" "hmac-sha384" "hmac-sha512"];
        default = "sha512";
        description = "Algorithm used to generate this TSIG key.";
      };
    };
  });
in {
  options.services.nameserver = with lib; {
    backend = {
      type = mkOption {
        type = types.nullOr (types.enum []);
        default = null;
        description = "The server backend implementing this configuration.";
      };
      user = mkOption {
        type = types.str;
        default = "nameserver";
        description = "User account under which to run the nameserver.";
      };
      group = mkOption {
        type = types.str;
        default = be.user;
        description = "User group under which to run the nameserver.";
      };
      # configuration for TSIG control of the daemon
      tsig = {
        keys = mkOption {
          type = submodule ({
            config,
            lib,
            ...
          }: {
            freefromType = keyModule;
            options = {
              local = mkOption {
                type = keyModule;
                description = "The key used for local control of the nameserver daemon.";
              };
            };
            config = {
              local = lib.mkDefault {
                file = "${be.stateDir}/tsig/local.tsig";
                algorithm = "hmac-sha512";
              };
            };
          });
          default = {};
          description = "Key descriptions for remote daemon control.";
        };
      };
      network = {
        ports = mkOption {
          type = types.listOf types.port;
          default = [53];
          description = "Ports on which to listen for DNS queries.";
        };
        tls = {
          ports = mkOption {
            type = types.listOf types.port;
            default = [853];
            description = "Ports on which to listen for DNS-over-TLS queries.";
          };
        };
        http = {
          ports = mkOption {
            type = types.listOf types.port;
            default = [80];
            description = "Ports on which to listen for DNS-over-HTTP queries.";
          };
        };
        https = {
          ports = mkOption {
            type = types.listOf types.port;
            default = [443];
            description = "Ports on which to listen for DNS-over-HTTPS queries.";
          };
        };
      };
      stateDirName = mkOption {
        type = types.str;
        default = "nameserver";
      };
      runDirName = mkOption {
        type = types.str;
        default = "nameserver";
      };
      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/${be.stateDirName}";
        description = "Stable state directory of the nameserver daemon. Will be created and `chown`ed to `\${user}:\${group}` during systemd service startup.";
        readOnly = true;
      };
      runDir = mkOption {
        type = types.str;
        default = "/run/${be.runDirName}";
        description = "Working directory of the nameserver daemon. Will be created and `chown`ed to `\${user}:\${group}` during systemd service startup.";
        readOnly = true;
      };
      systemd = {
        serviceName = mkOption {
          type = types.str;
          default = "nameserver";
        };
      };
    };
  };
  disabledModules = [];
  imports = [];
  config = lib.mkIf (be.type != null) {
    users.groups.${be.group} = {};
    users.users.${be.user} = {
      inherit (be) group;
      description = "nameserver daemon user";
      isSystemUser = true;
    };
    services.nameserver.backend.remote.keys."local" =
      lib.mkForce {
      };
    systemd.services.${be.systemd.serviceName} = {
      description = "DNS nameserver daemon";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = be.user;
        Group = be.group;
        ProtectHome = true;
        ProtectSystem = "full";
        RuntimeDirectory = [be.runDirName];
        RuntimeDirectoryMode = 0700;
        StateDirectory = [be.stateDirName];
        StateDirectoryMode = 0700;
      };
    };
  };
  meta = {};
}
