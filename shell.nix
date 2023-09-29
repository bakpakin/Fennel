(import (let
  lockFile = builtins.fromJSON (builtins.readFile ./flake.lock);
  info = lockFile.nodes.flake-compat.locked;
in builtins.fetchTarball {
  url = "https://api.${info.host or "github.com"}/repos/${info.owner}/${info.repo}/tarball/${info.rev}";
  ${if info ? narHash then "sha256" else null} = info.narHash;
}) { src = ./.; }).shellNix
