{
  description = "Replay - Recording/playback harness for deterministic testing of external effects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purs-nix.url = "https://flakehub.com/f/Cambridge-Vision-Technology/purs-nix/0.1.tar.gz";
    purs-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    purescript-whine = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/purescript-whine/0.1.tar.gz";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        purs-nix.follows = "purs-nix";
      };
    };

    agen = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/agen/0.1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    eslint-plugin-purescript-ffi = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/eslint-plugin-purescript-ffi/0.1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    purescript-dedup = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/purescript-dedup/*";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.purs-nix.follows = "purs-nix";
    };

    purescript-scythe = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/purescript-scythe/*";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.purs-nix.follows = "purs-nix";
    };

    purescript-drop = {
      url = "https://flakehub.com/f/Cambridge-Vision-Technology/purescript-drop/*";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.purs-nix.follows = "purs-nix";
    };

    purescript-overlay = {
      url = "github:thomashoneyman/purescript-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      purs-nix,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          system,
          inputs',
          ...
        }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.purescript-overlay.overlays.default ];
          };

          purs-nix-lib = purs-nix { inherit system; };

          nodejs = pkgs.nodejs_22;

          deps = pkgs.buildNpmPackage {
            pname = "replay-deps";
            version = "1.0.0";

            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./package.json
                ./package-lock.json
              ];
            };

            npmDepsHash = "sha256-4r1ZnN5bskh5A1GeTmwpFJeA4N1QIq6NX04ArCwsDmk=";
            inherit nodejs;

            dontNpmBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              ${pkgs.rsync}/bin/rsync -a --no-perms --no-owner --no-group node_modules $out/
              ${pkgs.rsync}/bin/rsync -a --no-perms --no-owner --no-group package.json $out/
              ${pkgs.rsync}/bin/rsync -a --no-perms --no-owner --no-group package-lock.json $out/
              runHook postInstall
            '';
          };

          # PureScript source for external consumers (oz, etc.)
          # This allows other flakes to include Replay.* modules in their compilation
          # Only export the Replay/ directory to avoid conflicts with consumer modules
          # (Main.purs, Signal.purs, FFI/, Json/ are replay-internal)
          psSrc = pkgs.runCommand "replay-ps-src" { } ''
            mkdir -p $out
            cp -r ${./src}/Replay $out/
          '';

          # Client SDK: only client-facing modules for consuming apps
          # Excludes server internals (Handler, Session, Player, Recorder,
          # Interceptor, IdTranslation, Server, Stream, Recording)
          # Includes supporting modules (FFI.Crypto, Json.Nullable) needed by SDK modules
          psClientSdk = pkgs.stdenvNoCC.mkDerivation {
            name = "replay-ps-client-sdk";
            src = pkgs.lib.fileset.toSource {
              root = ./src;
              fileset = pkgs.lib.fileset.unions [
                # Replay.Client
                ./src/Replay/Client.purs
                ./src/Replay/Client.js
                # Replay.Hash
                ./src/Replay/Hash.purs
                # Replay.PendingRequests
                ./src/Replay/PendingRequests.purs
                # Replay.Protocol.Envelope
                ./src/Replay/Protocol/Envelope.purs
                # Replay.Protocol.Types
                ./src/Replay/Protocol/Types.purs
                # Replay.TraceContext
                ./src/Replay/TraceContext.purs
                # Replay.TraceContext.Effect
                ./src/Replay/TraceContext/Effect.purs
                # Replay.ULID
                ./src/Replay/ULID.purs
                ./src/Replay/ULID.js
                # Replay.Time
                ./src/Replay/Time.purs
                # Replay.Common
                ./src/Replay/Common.purs
                # Replay.Types
                ./src/Replay/Types.purs
                # Supporting modules needed by SDK
                # FFI.Crypto (used by Replay.Hash)
                ./src/FFI/Crypto.purs
                ./src/FFI/Crypto.js
                # Json.Nullable (used by Replay.Protocol.Envelope, Replay.Protocol.Types)
                ./src/Json/Nullable.purs
              ];
            };
            installPhase = "cp -r $src $out";
          };

          ps = purs-nix-lib.purs {
            dependencies = [
              "aff"
              "aff-promise"
              "argonaut-core"
              "argonaut-codecs"
              "argonaut-generic"
              "arraybuffer-types"
              "arrays"
              "console"
              "datetime"
              "effect"
              "either"
              "exceptions"
              "foldable-traversable"
              "formatters"
              "integers"
              "maybe"
              "newtype"
              "node-buffer"
              "node-fs"
              "node-path"
              "node-process"
              "node-streams"
              "nullable"
              "optparse"
              "ordered-collections"
              "prelude"
              "refs"
              "strings"
              "transformers"
            ];
            srcs = [
              ./src
            ];
            compile = {
              compilerOptions = [ "--json-errors" ];
            };
          };

          psTest = purs-nix-lib.purs {
            dependencies = [
              "aff"
              "aff-promise"
              "argonaut-core"
              "argonaut-codecs"
              "argonaut-generic"
              "arraybuffer-types"
              "arrays"
              "console"
              "datetime"
              "effect"
              "either"
              "exceptions"
              "foldable-traversable"
              "formatters"
              "integers"
              "maybe"
              "newtype"
              "node-buffer"
              "node-fs"
              "node-path"
              "node-process"
              "node-streams"
              "nullable"
              "optparse"
              "ordered-collections"
              "prelude"
              "refs"
              "strings"
              "transformers"
            ];
            srcs = [
              ./src
              ./test
            ];
            compile = {
              compilerOptions = [ "--json-errors" ];
            };
          };

          psEchoClient = purs-nix-lib.purs {
            dependencies = [
              "aff"
              "aff-promise"
              "argonaut-core"
              "argonaut-codecs"
              "argonaut-generic"
              "arraybuffer-types"
              "arrays"
              "console"
              "datetime"
              "effect"
              "either"
              "exceptions"
              "foldable-traversable"
              "formatters"
              "integers"
              "maybe"
              "newtype"
              "node-buffer"
              "node-fs"
              "node-path"
              "node-process"
              "node-streams"
              "nullable"
              "optparse"
              "ordered-collections"
              "prelude"
              "refs"
              "strings"
              "transformers"
            ];
            srcs = [
              ./src
              ./examples/echo-client/src
            ];
            compile = {
              compilerOptions = [ "--json-errors" ];
            };
          };

          testUnitBundle = psTest.bundle {
            esbuild = {
              platform = "node";
              format = "esm";
              outfile = "test-unit.mjs";
              external = [
                "ws"
                "ulid"
                "json-stable-stringify"
              ];
            };
            module = "Test.Main";
            main = true;
          };

          echoClientBundle = psEchoClient.bundle {
            esbuild = {
              platform = "node";
              format = "esm";
              outfile = "echo-client.mjs";
              external = [
                "ws"
                "ulid"
                "json-stable-stringify"
              ];
            };
            module = "EchoClient.Main";
            main = true;
          };

          harnessBundle = ps.bundle {
            esbuild = {
              platform = "node";
              format = "esm";
              outfile = "replay-harness.mjs";
              external = [
                "ws"
                "ulid"
                "json-stable-stringify"
                "zstd-napi"
              ];
            };
            module = "Main";
            main = true;
          };

          harnessServer =
            pkgs.runCommand "replay-harness"
              {
                buildInputs = [ nodejs ];
              }
              ''
                mkdir -p $out/bin
                cp -r ${deps}/node_modules $out/
                cp ${harnessBundle} $out/replay-harness.mjs
                cat > $out/bin/replay <<'SCRIPT'
                #!${pkgs.bash}/bin/bash
                set -euo pipefail
                SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")/.." && pwd)"
                export NODE_PATH="$SCRIPT_DIR/node_modules"
                exec ${nodejs}/bin/node "$SCRIPT_DIR/replay-harness.mjs" "$@"
                SCRIPT
                chmod +x $out/bin/replay
              '';

          bddTestSource = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./features
              ./cucumber.js
            ];
          };

          echoClient =
            pkgs.runCommand "replay-echo-client"
              {
                buildInputs = [ nodejs ];
              }
              ''
                mkdir -p $out/bin
                cp -r ${deps}/node_modules $out/
                cp ${echoClientBundle} $out/echo-client.mjs
                cat > $out/bin/echo-client <<'SCRIPT'
                #!${pkgs.bash}/bin/bash
                set -euo pipefail
                SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")/.." && pwd)"
                export NODE_PATH="$SCRIPT_DIR/node_modules"
                exec ${nodejs}/bin/node "$SCRIPT_DIR/echo-client.mjs" "$@"
                SCRIPT
                chmod +x $out/bin/echo-client
              '';

          testUnit =
            pkgs.runCommand "replay-test-unit"
              {
                buildInputs = [ nodejs ];
              }
              ''
                mkdir -p $out/bin
                cp -r ${deps}/node_modules $out/
                cp ${testUnitBundle} $out/test-unit.mjs
                cat > $out/bin/test-unit <<'SCRIPT'
                #!${pkgs.bash}/bin/bash
                set -euo pipefail
                SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")/.." && pwd)"
                export NODE_PATH="$SCRIPT_DIR/node_modules"
                exec ${nodejs}/bin/node "$SCRIPT_DIR/test-unit.mjs" "$@"
                SCRIPT
                chmod +x $out/bin/test-unit
              '';

          prettierWrapped = pkgs.writeShellScriptBin "prettier" ''
            export CACHE_DIR=$(${pkgs.coreutils}/bin/mktemp -d)
            exec ${pkgs.nodePackages.prettier}/bin/prettier "$@"
          '';

          helpersSource = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./helpers/package.json
              ./helpers/src
            ];
          };

          helpers =
            pkgs.runCommand "replay-helpers"
              {
                buildInputs = [ nodejs ];
              }
              ''
                mkdir -p $out
                cp -r ${helpersSource}/helpers/* $out/
                cp -r ${deps}/node_modules $out/
              '';

        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              prettier.enable = true;
              prettier.package = prettierWrapped;
            };
            settings.formatter = {
              prettier = {
                excludes = [
                  "node_modules/**"
                  "output/**"
                  "out/**"
                  "result/**"
                  "package-lock.json"
                  "replay-recording-test/invalid-json-test.json"
                ];
              };
              purs-tidy = {
                command = "${pkgs.purs-tidy}/bin/purs-tidy";
                options = [ "format-in-place" ];
                includes = [ "*.purs" ];
              };
            };
          };

          packages = {
            default = harnessServer;
            inherit
              deps
              testUnit
              echoClient
              harnessServer
              helpers
              psSrc
              psClientSdk
              ;
          };

          checks = {
            format = config.treefmt.build.check config.treefmt.projectRoot;
            test-unit =
              pkgs.runCommand "check-test-unit"
                {
                  buildInputs = [ nodejs ];
                }
                ''
                  cp -r ${deps}/node_modules ./
                  export NODE_PATH="$(pwd)/node_modules"
                  ${nodejs}/bin/node ${testUnit}/test-unit.mjs
                  touch $out
                '';
            test-playback =
              pkgs.runCommand "replay-test-playback"
                {
                  buildInputs = [ nodejs ];
                }
                ''
                  export REPLAY_HARNESS_BINARY="${harnessServer}/bin/replay"
                  export ECHO_CLIENT_BINARY="${echoClient}/bin/echo-client"
                  export REPLAY_TEST_MODE="playback"

                  mkdir -p work
                  cp -r ${bddTestSource}/features work/
                  cp ${bddTestSource}/cucumber.js work/
                  cp -r ${deps}/node_modules work/

                  cd work
                  ${nodejs}/bin/node node_modules/.bin/cucumber-js \
                    --config cucumber.js \
                    features/playback_mode.feature \
                    features/intercept_playback_sync.feature

                  touch $out
                '';
            wrapper-shebangs = pkgs.runCommand "check-wrapper-shebangs" { } ''
              fail=0
              for script in \
                ${harnessServer}/bin/replay \
                ${echoClient}/bin/echo-client \
                ${testUnit}/bin/test-unit; do
                shebang=$(head -n1 "$script")
                if echo "$shebang" | grep -q '/usr/bin/env'; then
                  echo "FAIL: $script has shebang using /usr/bin/env: $shebang"
                  fail=1
                else
                  echo "OK: $script shebang: $shebang"
                fi
              done
              if [ "$fail" -ne 0 ]; then
                echo ""
                echo "Wrapper scripts must not use /usr/bin/env in their shebang."
                echo "Use Nix store bash path instead of /usr/bin/env."
                exit 1
              fi
              touch $out
            '';
          };

          apps = {
            format-fix = {
              type = "app";
              program = toString (
                pkgs.writeShellScript "replay-format-fix" ''
                  set -euo pipefail
                  echo "Formatting all files with treefmt (Nix + JavaScript + PureScript)..."
                  exec ${config.treefmt.build.wrapper}/bin/treefmt "$@"
                ''
              );
              meta.description = "Fix code formatting (Nix + JavaScript + PureScript)";
            };

            test-unit = {
              type = "app";
              program = "${testUnit}/bin/test-unit";
              meta.description = "Run unit tests";
            };

            echo-client = {
              type = "app";
              program = "${echoClient}/bin/echo-client";
              meta.description = "Demo app: Echo client for httpbin.org";
            };

            default = {
              type = "app";
              program = "${harnessServer}/bin/replay";
              meta.description = "Replay harness server";
            };

            test-live = {
              type = "app";
              program = toString (
                pkgs.writeShellScript "replay-test-live" ''
                  set -euo pipefail

                  echo "Running BDD tests in LIVE mode (real HTTP requests)..."
                  echo ""

                  export REPLAY_HARNESS_BINARY="${harnessServer}/bin/replay"
                  export ECHO_CLIENT_BINARY="${echoClient}/bin/echo-client"
                  export REPLAY_TEST_MODE="live"

                  # Create a temporary directory and copy test source there
                  WORK_DIR=$(mktemp -d)
                  trap "rm -rf $WORK_DIR" EXIT

                  cp -r ${bddTestSource}/features "$WORK_DIR/"
                  cp ${bddTestSource}/cucumber.js "$WORK_DIR/"
                  cp -r ${deps}/node_modules "$WORK_DIR/"

                  cd "$WORK_DIR"
                  exec ${nodejs}/bin/node node_modules/.bin/cucumber-js \
                    --config cucumber.js \
                    features/live_mode.feature \
                    "$@"
                ''
              );
              meta.description = "Run BDD tests with real HTTP requests (no recording)";
            };

            test-record = {
              type = "app";
              program = toString (
                pkgs.writeShellScript "replay-test-record" ''
                  set -euo pipefail

                  echo "Running BDD tests in RECORD mode (capturing fixtures)..."
                  echo ""

                  export REPLAY_HARNESS_BINARY="${harnessServer}/bin/replay"
                  export ECHO_CLIENT_BINARY="${echoClient}/bin/echo-client"
                  export REPLAY_TEST_MODE="record"
                  ORIG_DIR="$(pwd)"

                  # Create a working directory with writable fixtures space
                  WORK_DIR=$(mktemp -d)
                  cleanup() {
                    # Unlink node_modules first (it's from Nix store, can't delete)
                    rm -f "$WORK_DIR/node_modules" 2>/dev/null || true
                    rm -rf "$WORK_DIR" 2>/dev/null || true
                  }
                  trap cleanup EXIT

                  # Copy source files, symlink node_modules
                  cp cucumber.js "$WORK_DIR/"
                  cp -r features "$WORK_DIR/"
                  ln -s ${deps}/node_modules "$WORK_DIR/node_modules"

                  cd "$WORK_DIR"
                  ${nodejs}/bin/node node_modules/.bin/cucumber-js \
                    --config cucumber.js \
                    features/live_mode.feature \
                    features/record_mode.feature \
                    "$@"
                  exit_code=$?

                  # Copy back any new fixtures
                  if [ -d "$WORK_DIR/features/fixtures" ]; then
                    mkdir -p "$ORIG_DIR/features/fixtures"
                    cp -r "$WORK_DIR/features/fixtures/"* "$ORIG_DIR/features/fixtures/" 2>/dev/null || true
                  fi

                  exit $exit_code
                ''
              );
              meta.description = "Run BDD tests and capture fixtures";
            };

            test-playback = {
              type = "app";
              program = toString (
                pkgs.writeShellScript "replay-test-playback" ''
                  set -euo pipefail

                  echo "Running BDD tests in PLAYBACK mode (using fixtures)..."
                  echo ""

                  export REPLAY_HARNESS_BINARY="${harnessServer}/bin/replay"
                  export ECHO_CLIENT_BINARY="${echoClient}/bin/echo-client"
                  export REPLAY_TEST_MODE="playback"

                  # Create a temporary directory and copy test source there
                  WORK_DIR=$(mktemp -d)
                  trap "rm -rf $WORK_DIR" EXIT

                  cp -r ${bddTestSource}/features "$WORK_DIR/"
                  cp ${bddTestSource}/cucumber.js "$WORK_DIR/"
                  cp -r ${deps}/node_modules "$WORK_DIR/"

                  cd "$WORK_DIR"
                  exec ${nodejs}/bin/node node_modules/.bin/cucumber-js \
                    --config cucumber.js \
                    features/playback_mode.feature \
                    features/intercept_playback_sync.feature \
                    "$@"
                ''
              );
              meta.description = "Run BDD tests with recorded fixtures";
            };
          };

          devShells.default = pkgs.mkShell {
            buildInputs = [
              nodejs
              pkgs.nodePackages.prettier
              pkgs.nodePackages.eslint
              pkgs.purs-tidy
              pkgs.nixfmt
              pkgs.statix
              pkgs.deadnix
              pkgs.fd

              (ps.command { })
              inputs'.purescript-dedup.packages.default
              inputs'.purescript-scythe.packages.default
              inputs'.purescript-drop.packages.default
              inputs'.agen.packages.default
            ];

            shellHook = ''
              echo "======================================="
              echo "Replay Development Environment"
              echo "======================================="
              echo "Node.js: $(${nodejs}/bin/node --version)"
              echo ""
              echo "Commands:"
              echo "  nix flake check         - Run all checks"
              echo "  nix fmt                 - Format all files"
              echo "  nix run .#format-fix    - Format all files"
              echo "  nix run .#test-unit     - Run unit tests"
              echo "  nix run .#test-live     - Run BDD tests (live HTTP)"
              echo "  nix run .#test-record   - Run BDD tests (record fixtures)"
              echo "  nix run .#test-playback - Run BDD tests (playback fixtures)"
              echo "  nix run .#echo-client   - Demo echo client"
              echo ""
            '';
          };
        };
    };
}
