{
  description = "raylib-zig project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShells.default = pkgs.mkShell {
          name = "raylib-zig-shell";

          buildInputs = with pkgs; [
            zig
            raylib
            pkg-config
            gcc

            libx11
            libxcursor
            libxext
            libxfixes
            libxi
            libxinerama
            libxrandr
            libxrender
          ];

          LD_LIBRARY_PATH = "${pkgs.raylib}/lib";
        };

        # Dummy package — required for flakes to not cry
        packages.default = pkgs.stdenv.mkDerivation {
          name = "raylib-zig-placeholder";
          src = ./.;
          installPhase = "mkdir -p $out";
        };
      });
}

