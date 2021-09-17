{
  description = "A very basic flake";

  # inputs.nix.url = "github:nixos/nix";
  inputs.prebuiltNix = {
    url = "path:/home/regnat/Repos/github.com/nixos/nix/rootless-daemon/outputs/out";
    flake = false;
  };

  outputs = { self, nixpkgs, nix, prebuiltNix }:
  let
    buildExpr = config:
      let pkgs = config.nixpkgs.pkgs; in
      pkgs.writeText "build-expr.nix" ''
        let utils = builtins.storePath ${config.system.build.extraUtils}; in
        derivation {
          name = "hello";
          system = "${config.nixpkgs.localSystem.system}";
          PATH = "''${utils}/bin";
          builder = "''${utils}/bin/sh";
          args = [ "-c" "echo Hello; mkdir $out; echo Hello > $out/hello" ];
        }
      '';
  in
  {

    # nixPackage = nix.defaultPackage.x86_64-linux;
    nixPackage = nixpkgs.legacyPackages.x86_64-linux.runCommand "nix-static" {
      version = "2.4pre20210824_dirty";
    } ''
      cp -r ${prebuiltNix} $out
      chmod +x $out/bin/*
      chmod -R +w $out/lib
      find $out/lib -type f -exec sed -i "s#/home/regnat/Repos/github.com/nixos/nix/rootless-daemon/outputs/out#$out#g" {} \+
    '';

    nixosTests.rootDaemon = nixpkgs.legacyPackages."x86_64-linux".nixosTest {
      machine = { config, pkgs, lib, ... }:
      {
        users.users.alice.isNormalUser = true;
        users.users.nix-daemon.isSystemUser = true;
        users.users.nix-daemon.group = "nix-daemon";
        users.groups.nix-daemon = {};
        environment.variables.NIX_REMOTE = "daemon"; # Even for root
        virtualisation.writableStore = true;

        nix.package = self.nixPackage;

        systemd.services.nix-daemon.serviceConfig = {
          User = "nix-daemon";
          Group = "nix-daemon";
          ExecStartPre = "+" + pkgs.writeScriptBin "nix-daemon-pre-start" ''
            #! ${pkgs.stdenv.shell} -e
            chown nix-daemon:nix-daemon /nix
            mount -o remount,rw /nix/store
            chown nix-daemon:nix-daemon /nix/store
            mount -o remount,ro /nix/store
            chown -R nix-daemon:nix-daemon /nix/var
          '' + "/bin/nix-daemon-pre-start";
        };
      };

      testScript = { nodes }:
        let pkgs = nodes.machine.config.nixpkgs.pkgs; in
        ''
          machine.start()
          machine.wait_for_unit("nix-daemon.socket")
          machine.succeed(
            "${pkgs.util-linux}/bin/runuser -u alice -- nix-build ${buildExpr nodes.machine.config} -o /home/alice/hello --option substitute false"
          )
          machine.succeed(
            "nix-collect-garbage"
          )
          machine.succeed(
            "cat /home/alice/hello/hello"
          )
        '';
    };

    devShell.x86_64-linux =
      let pkgs = nixpkgs.legacyPackages.x86_64-linux; in
      pkgs.mkShell {
        buildInputs = [
          pkgs.vagrant
          pkgs.ansible
        ];
      };

  };
}
