{
  description = "My Python App with Nix and uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Core pyproject-nix ecosystem tools
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";

    # Ensure consistent dependencies between these tools
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  };

  outputs = { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python312; # Your desired Python version

        # 1. Load Project Workspace (parses pyproject.toml, uv.lock)
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.; # Root of your flake/project
        };

        # 2. Generate Nix Overlay from uv.lock (via workspace)
        uvLockedOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # Or "sdist"
        };

        # 3. Placeholder for Your Custom Package Overrides
        myCustomOverrides = final: prev: {
          /* e.g., some-package = prev.some-package.overridePythonAttrs (...); */

          pytorch-triton-rocm =
            prev."pytorch-triton-rocm".overrideAttrs (oldAttrs: rec {
            buildInputs =
              (oldAttrs.buildInputs or []) ++ [
                pkgs.zlib
                pkgs.zstd
                pkgs.xz
                pkgs.bzip2
              ];
          });
          torch = prev.torch.overrideAttrs (oldAttrs: rec {
            buildInputs =
              (oldAttrs.buildInputs or []) ++ [
                pkgs.rocmPackages.rocblas
                pkgs.zlib
                pkgs.zstd
                pkgs.xz
                pkgs.bzip2
              ];
          });

        };

        # 4. Construct the Final Python Package Set
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; })
          .overrideScope (nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default # For build tools
            uvLockedOverlay                          # Your locked dependencies
            myCustomOverrides                        # Your fixes
          ]);

        # --- This is where your project's metadata is accessed ---
        projectNameInToml = "marker-pdf"; # MUST match [project.name] in pyproject.toml!
        thisProjectAsNixPkg = pythonSet.${projectNameInToml};
        # ---

        # 5. Create the Python Runtime Environment
        appPythonEnv = pythonSet.mkVirtualEnv 
          (thisProjectAsNixPkg.pname + "-env") 
          workspace.deps.default; # Uses deps from pyproject.toml [project.dependencies]

      in
      {
        # Development Shell
        devShells.default = pkgs.mkShell {
          packages = [ appPythonEnv pkgs.ruff pkgs.uv ];
          shellHook = '' /* Your custom shell hooks */ '';
        };

        # Nix Package for Your Application
        packages.default = pkgs.stdenv.mkDerivation {
          pname = thisProjectAsNixPkg.pname;
          version = thisProjectAsNixPkg.version;
          src = ./.; # Source of your main script

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ appPythonEnv ]; # Runtime Python environment

          installPhase = ''
            mkdir -p $out/bin

            cp convert.py "$out/bin/marker"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker"

            cp convert_single.py "$out/bin/marker_single"
            chmod +x "$out/bin/marker_single"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker_single"

            cp chunk_convert.py "$out/bin/marker_chunk_convert"
            chmod +x "$out/bin/marker_chunk_convert"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker_chunk_convert"

            cp marker_app.py "$out/bin/marker_gui"
            chmod +x "$out/bin/marker_gui"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker_gui"

            cp extraction_app.py "$out/bin/marker_extract"
            chmod +x "$out/bin/marker_extract"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker_extract"

            cp marker_server.py "$out/bin/marker_server"
            chmod +x "$out/bin/marker_server"
            sed -i "1i#!/usr/bin/env ${appPythonEnv}/bin/python" "$out/bin/marker_server"

            # INFO: keep for future reference
            # cp main.py $out/bin/${thisProjectAsNixPkg.pname}-script
            # chmod +x $out/bin/${thisProjectAsNixPkg.pname}-script
            # makeWrapper ${appPythonEnv}/bin/python $out/bin/${thisProjectAsNixPkg.pname} \
            #   --add-flags $out/bin/${thisProjectAsNixPkg.pname}-script

          '';
        };
        packages.${thisProjectAsNixPkg.pname} = self.packages.${system}.default;

        # App for `nix run`
        # apps.default = {
        #   type = "app";
        #   program = "${self.packages.${system}.default}/bin/${thisProjectAsNixPkg.pname}";
        # };
        # apps.${thisProjectAsNixPkg.pname} = self.apps.${system}.default;
      }
    );
}
