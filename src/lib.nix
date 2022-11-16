{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  submodule = module: lib.types.submoduleWith {modules = [module];};
  dlib = config.lib.services.nameserver;
  mkToString = fn: args:
    lib.mkOption ({
        type = types.anything;
        default = fn;
        readOnly = true;
        description = "Function that converts this submodule to a string.";
      }
      // args);
in {
  options.services.nameserver = with lib; {};
  disabledModules = [];
  imports = [];
  config = {
    lib.services.nameserver = with lib; {
      # convert various record modules to zone file strings
      record.toZFString' = r: "${r.name} ${r.class} ${toString r.ttl}";
      record.toZFString = r: name: "${dlib.record.toZFString' r} ${name} ${toString r.value}";
      record.soa.toZFString = soa: "${dlib.record.toZFString' soa} SOA ${soa.mname} ${soa.rname} ( ${toString soa.serial} ${toString soa.refresh} ${toString soa.retry} ${toString soa.expire} ${toString soa.minimum})";
      record.a.toZFString = a: dlib.record.toZFString a "A";
      record.aaaa.toZFString = aaaa: dlib.record.toZFString aaaa "AAAA";
      record.cname.toZFString = cname: dlib.record.toZFString cname "CNAME";
      record.mx.toZFString = mx: dlib.record.toZFString mx "MX";
      record.ns.toZFString = ns: dlib.record.toZFString ns "NS";
      record.srv.toZFString = srv: dlib.record.toZFString srv "SRV";
      # convert zone definition to zone file string
      zone.toZFString = zone:
        "$ORIGIN ${zone.origin}\n"
        + (std.optionalString (zone.include != null) ("$INCLUDE ${zone.include.path}" + (std.optionalString (zone.include.origin != null) " ${zone.include.origin}\n")))
        + (std.optionalString (zone.ttl != null) "$TTL ${toString zone.ttl}\n");
      # zone definition
      types.record.generic = type: vType:
        submodule (args @ {
          config,
          lib,
          ...
        }: {
          options = with lib; {
            name = mkOption ({type = types.str;}
              // (
                if args ? name
                then {default = args.name;}
                else {}
              ));
            ttl = mkOption {type = types.int;};
            class = mkOption {
              type = types.str;
              default = "IN";
            };
            type = mkOption {
              type = types.str;
              default = type;
              description = "The type of this record.";
              readOnly = true;
            };
            value = mkOption {type = vType;};
            __toString = mkToString (self: "${self.name} ${toString self.ttl} ${self.class} ${self.type} ${toString self.value}") {
              description = "Function that converts this record to a zone file string. Should be provided by the implementation. Do not modify. Automatically called by `builtins.toString`.";
            };
          };
        });
      types.record.basic = type: dlib.types.record.generic type types.str;
      types.record.soa = dlib.types.record.generic "SOA" (submodule (args @ {
        config,
        lib,
        ...
      }: {
        options = with lib; {
          mname = mkOption {type = types.str;};
          rname = mkOption {type = types.str;};
          serial = mkOption {type = types.int;};
          refresh = mkOption {type = types.int;};
          retry = mkOption {type = types.int;};
          expire = mkOption {type = types.int;};
          minimum = mkOption {type = types.int;};
          __toString = mkToString (self: "${self.mname} ${self.rname} ( ${toString self.serial} ${toString self.refresh} ${toString self.retry} ${toString self.expire} ${toString self.minimum} )") {};
        };
      }));
      types.zone = submodule (args @ {
        config,
        lib,
        ...
      }: {
        options = with lib; {
          origin = mkOption ({type = types.str;}
            // (
              if args ? name
              then {default = args.name;}
              else {}
            ));
          include = mkOption {
            type = types.nullOr (submodule ({
              config,
              lib,
              ...
            }: {
              options = with lib; {
                path = mkOption {type = types.path;};
                origin = mkOption {
                  type = types.str;
                  default = config.origin;
                };
                __toString = mkToString (self: "${self.path}" + (std.optionalString (self.origin != config.origin) " ${self.origin}")) {};
              };
            }));
          };
          primaries = mkOption {
            type = types.listOf types.str;
            default = [];
          };
          secondaries = mkOption {
            type = types.listOf types.str;
            default = [];
          };
          isPrimary = mkOption {
            type = types.bool;
            default = config.primaries == [];
            readOnly = true;
            description = "Whether this nameserver is a primary for this zone.";
          };
          records = let
            basic = dlib.types.record.basic;
          in
            mkOption {
              type = submodule ({
                config,
                lib,
                ...
              }: {
                options = with lib; {
                  soa = mkOption {
                    type = types.attrsOf dlib.types.record.soa;
                    default = {};
                  };
                  a = mkOption {
                    type = types.attrsOf (types.listOf (basic "A"));
                    default = {};
                  };
                };
              });
              default = {};
              description = "Attribute set of DNS records, mapping `record type` -> `host name`.";
            };
          __toString = mkToString (
            self:
              concatStringsSep "\n" (
                ["$ORIGIN ${self.origin}"]
                ++ (std.optional (self.ttl != null) "$TTL ${toString self.ttl}")
                ++ (std.optional (self.include != null) "$INCLUDE ${toString self.include}")
              )
          ) {description = "Called by `builtins.toString` to convert this zone to a zone file string. Do not override.";};
          file = mkOption {
            type = types.path;
            default = pkgs.writeText "${config.origin}.zone" (toString config);
            readOnly = true;
            description = "A path to a zone file serialized from this zone config.";
          };
        };
        imports = [];
        config = {};
      });
    };
  };
  meta = {};
}
