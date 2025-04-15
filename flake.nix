{
  # Flake description
  description = "MonOS dev environment";

  # Dependencies
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # Actions
  outputs = { nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem(system: let
    includeDir = "./include";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [ ];
    };
  in with pkgs; {
    devShells.default = mkShell {
      buildInputs = [ zig nasm qemu libisoburn wget ];
      shellHook = '''';
    };
  });
}
