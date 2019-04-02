{ pkgs ? import <nixpkgs> {  } }:

pkgs.mkShell rec {
  name = "fennel-env";
  buildInputs = [
    pkgs.cloc
    (pkgs.callPackage ({ stdenv, lua5_1, lua5_2, lua5_3, luajit }:
    stdenv.mkDerivation rec {
      name = "lua-wrappers";
      unpackPhase = ":";
      installPhase = ''
        mkdir -p $out/bin
        ln -s ${lua5_1}/bin/lua $out/bin/lua5.1
        ln -s ${lua5_2}/bin/lua $out/bin/lua5.2
        ln -s ${lua5_3}/bin/lua $out/bin/lua5.3
        ln -s ${luajit}/bin/lua $out/bin/luajit
      '';
    }) { })
    pkgs.luaPackages.luacheck
  ];
}
