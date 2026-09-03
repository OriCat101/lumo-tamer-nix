{
  description = "Use Proton's private AI assistant anywhere: OpenAI-compatible API and CLI for Lumo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    lumo-tamer = {
      url = "github:ZeroTricks/lumo-tamer/v0.6.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      lumo-tamer,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        version = "main";
        src = lumo-tamer;

        # Build the Go authentication helper
        proton-auth = pkgs.buildGoModule {
          pname = "proton-auth";
          inherit version src;

          modRoot = "src/auth/login/go";
          subPackages = [ "." ];

          vendorHash = "sha256-S0b+VQFbIG6UtkZUHyz9+g6nq7c9/YTKUzkX+d8i2Ko=";

          meta = with pkgs.lib; {
            description = "Proton authentication helper for lumo-tamer";
            license = licenses.gpl3Only;
            mainProgram = "proton-auth";
          };
        };
        buildInputs = with pkgs; [
          cairo
          pixman
          libpng
          libjpeg
          giflib
          librsvg
          pango
          libsecret
        ];
      in
      {
        packages = {
          lumo-tamer = pkgs.buildNpmPackage {
            pname = "lumo-tamer";
            inherit version src buildInputs;

            npmDepsHash = "sha256-Uq2QKNXk8CBPxgegJW0UipTRZErTx9UMr3LWHZrfgEE=";

            nativeBuildInputs = with pkgs; [
              nodejs_22
              pkg-config
              autoPatchelfHook
              makeWrapper
            ];

            # Upstream resolves every path (config, vault, logs, sessions) relative to
            # the directory the code lives in, which is read-only in the Nix store.
            # Split it: PACKAGE_ROOT for bundled files, PROJECT_ROOT for mutable state,
            # the latter overridable through $LUMO_TAMER_HOME.
            postPatch = ''
              substituteInPlace src/app/paths.ts \
                --replace-fail "export const PROJECT_ROOT = isCompiledDist" \
                               "export const PACKAGE_ROOT = isCompiledDist"

              cat ${./paths.ts} >> src/app/paths.ts

              substituteInPlace src/app/config-file.ts \
                --replace-fail "import { resolveProjectPath } from './paths.js';" \
                               "import { resolveProjectPath, resolvePackagePath } from './paths.js';" \
                --replace-fail "resolveProjectPath('config.defaults.yaml')" \
                               "resolvePackagePath('config.defaults.yaml')"

              substituteInPlace config.defaults.yaml \
                --replace-fail 'binaryPath: "./dist/proton-auth"' \
                               'binaryPath: "${pkgs.lib.getExe proton-auth}"'
            '';

            # Fixes a bug where a raw (unfenced) tool-call JSON followed in the same
            # chunk by a stray, unmatched closing ``` gets misdetected as a code fence
            # opener, silently swallowing the whole tool call as inert text -- the agent
            # turn then just stops instead of executing the tool. See the patch file
            # for the full explanation.
            patches = [ ./streaming-tool-detector-fence-priority.patch ];

            dontNpmBuild = true;

            buildPhase = ''
              runHook preBuild
              npm run build
              npm prune --omit=dev
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/lib/node_modules/lumo-tamer
              cp -r dist package.json package-lock.json config.defaults.yaml node_modules \
                $out/lib/node_modules/lumo-tamer/

              rm -f $out/lib/node_modules/lumo-tamer/node_modules/lumo-node
              rm -f $out/lib/node_modules/lumo-tamer/node_modules/proton-node

              makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/tamer \
                --add-flags "$out/lib/node_modules/lumo-tamer/dist/src/tamer.js" \
                --run 'export LUMO_TAMER_HOME="''${LUMO_TAMER_HOME:-''${XDG_STATE_HOME:-$HOME/.local/state}/lumo-tamer}"' \
                --run 'mkdir -p "$LUMO_TAMER_HOME/sessions"'

              ln -s tamer $out/bin/lumo-tamer

              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Use Proton's private AI assistant anywhere: OpenAI-compatible API and CLI for Lumo";
              homepage = "https://github.com/ZeroTricks/lumo-tamer";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "tamer";
            };
          };

          default = self.packages.${system}.lumo-tamer;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            self.packages.${system}.lumo-tamer
          ];
          shellHook = ''
            tamer --help
          '';
        };
      }
    );
}
