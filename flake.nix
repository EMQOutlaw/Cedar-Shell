{
  description = "CEDAR shell and reversible Hyprland compatibility tools";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAll (system:
        let pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "cedar-shell";
        };
        in rec {
          cedar = pkgs.callPackage ./packaging/nix/package.nix { src = self; };
          default = cedar;
        });
      homeManagerModules.default = import ./packaging/nix/home-manager.nix self;
      checks = forAll (system: {
        package = self.packages.${system}.cedar;
      });
    };
}
