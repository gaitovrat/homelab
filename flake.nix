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
    in
    {
      devShells = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              # Ansible itself comes from .github/requirements-lint.txt (see shellHook),
              # so local runs use exactly the versions CI lints with.
              python314

              # Cluster
              kubectl
              kubernetes-helm
              kubeseal
              kubectx # also provides kubens
              argocd
              jq

              # Cloudflare (terraform/cloudflare)
              opentofu

              # Repo and CI
              git
              gh
              actionlint
              shellcheck
              openssh
            ];

            shellHook = ''
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
            '';
          };
        }
      );
    };
}
