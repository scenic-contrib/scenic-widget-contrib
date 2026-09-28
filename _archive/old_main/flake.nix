{
  description = "JediLuke's Elixir nix-flake.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = nixpkgs.lib;

        elixir = pkgs.beam.packages.erlang.elixir;
        locales = pkgs.glibcLocales;
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = [
            elixir
            locales
          ];
        };
      }
    );
}