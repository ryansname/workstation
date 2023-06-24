{
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/bc3ec5eaa759.tar.gz") {} 
}: 

let 
  pkgs_rl = import (fetchTarball "https://github.com/ryansname/nix/archive/a664cdd.tar.gz") { inherit pkgs; };
in
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.curlFull
    pkgs.glfw
    (pkgs_rl.zig { version = "0.11.0-dev.3704+729a051e9"; })
  ];
  
  buildInputs = [
  ];
}
