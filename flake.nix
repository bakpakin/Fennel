# SPDX-LicenseIdentifier: MIT
# SPDX-FileCopyrightText: Calvin Rose and contributors
{
  description = "Lua Lisp language";

  inputs.flake-compat.flake = false;
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  inputs.flake-parts.url = "flake:flake-parts";
  inputs.nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
  inputs.systems.flake = false;
  inputs.systems.url = "flake:systems";

  outputs = { ... } @ inputs: inputs.flake-parts.lib.mkFlake {
    inherit inputs;
  } ({ config, flake-parts-lib, getSystem, inputs, lib, options, ... }:
    let
      rootConfig = config;
      rootOptions = options;
    in {
      _file = ./flake.nix;
      imports = [ ];
      config.perSystem = { config, inputs', nixpkgs, options, pkgs, system, ... }:
        let
          systemConfig = config;
          systemOptions = options;
        in {
          _file = ./flake.nix;
          config.devShells.default = pkgs.callPackage
            ({ mkShell
            , fennelCheckAll
            }:
            mkShell {
              name = "fennel";

              inputsFrom = [ fennelCheckAll ];
            })
            { inherit (config.packages) fennelCheckAll; };
          config.packages.fennel = pkgs.callPackage
            ({ lib, stdenv
            , lua
            }: stdenv.mkDerivation (attrsFinal: {
              pname = "fennel";
              version = let
                inherit (builtins) elemAt match readFile;
                source = readFile (attrsFinal.src + /src/fennel/utils.fnl);
                versionMatch = match ''.*\(local version :([^() \n]*)\).*'' source;
              in elemAt versionMatch 0;

              src = ./.;

              propagatedBuildInputs = [ (lib.getDev lua) ];

              makeFlags = [ "PREFIX=$(out)" ];

              doCheck = true;
            }))
            { };
          config.packages.fennelCheckAll = pkgs.callPackage
            ({ lib, linkFarm, fennel
            , lua5_1, lua5_2, lua5_3, lua5_4, luajit
            }: fennel.overrideAttrs (attrsFinal: attrsPrev: let
              luaBinLink = lua: executable:
                let
                  executable' = if executable != null then executable else
                    "${lua.executable}${lua.luaversion}";
                in linkFarm "${executable'}-bin" [
                  {
                    name = "bin/${executable'}";
                    path = "${lib.getBin lua}/bin/${lua.executable}";
                  }
                ];
            in {
              checkTarget = "testall";

              checkInputs = attrsPrev.checkInputs or [ ] ++ [
                (luaBinLink lua5_1 null)
                (luaBinLink lua5_2 null)
                (luaBinLink lua5_3 null)
                (luaBinLink lua5_4 null)
                (luaBinLink luajit "luajit")
              ];
            }))
            { inherit (config.packages) fennel; };
        };
      config.systems = import inputs.systems;
  });
}
