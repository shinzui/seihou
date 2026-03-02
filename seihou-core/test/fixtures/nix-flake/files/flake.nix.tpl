{
  description = "{{nix.description}}";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  outputs = { self, nixpkgs }: {
    packages.{{nix.system}}.default = nixpkgs.legacyPackages.{{nix.system}}.hello;
  };
}
