{
  description = "homelab: dev shell with every tool needed to work on this repo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux" # WSL, Linux PCs
        "aarch64-darwin" # Apple Silicon Macs
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f nixpkgs.legacyPackages.${system}
        );
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            # Ansible itself comes from .github/requirements-lint.txt (see shellHook),
            # so local runs use exactly the versions CI lints with.
            python314

            # Cluster
            kubectl
            kubernetes-helm
            kubeseal
            jq

            # Repo and CI
            git
            gh
            actionlint
            shellcheck
            openssh
          ];

          shellHook = ''
            # Python venv with ansible-core and ansible-lint pinned in .github/requirements-lint.txt.
            # Rebuilt only when that file or the Python interpreter changes.
            req=.github/requirements-lint.txt
            stamp="$(sha256sum "$req" | cut -d' ' -f1)-${pkgs.python314.version}"
            if [ "$(cat .venv/.stamp 2>/dev/null)" != "$stamp" ]; then
              echo "homelab: setting up .venv from $req" >&2
              rm -rf .venv
              ${pkgs.python314}/bin/python3 -m venv .venv \
                && .venv/bin/pip install --quiet --disable-pip-version-check -r "$req" \
                && echo "$stamp" > .venv/.stamp
            fi
            export VIRTUAL_ENV="$PWD/.venv"
            export PATH="$VIRTUAL_ENV/bin:$PATH"

            # Ansible, ssh and kubectl reach the nodes over Tailscale. tailscaled is a system
            # daemon, so it can't come from this shell; install it per machine (see README).
            if ! command -v tailscale >/dev/null; then
              echo "homelab: tailscale not installed; nodes are only reachable over the tailnet (see README, Tools)" >&2
            elif ! tailscale status >/dev/null 2>&1; then
              echo "homelab: tailscale is not connected; run 'sudo tailscale up' (Linux/WSL) or open the app (macOS)" >&2
            fi
          '';
        };
      });
    };
}
