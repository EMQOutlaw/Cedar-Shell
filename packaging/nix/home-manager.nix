flake: { config, lib, pkgs, ... }:
let cfg = config.programs.cedar;
in {
  options.programs.cedar = {
    enable = lib.mkEnableOption "CEDAR shell tools (does not replace a running desktop)";
    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    sessionTarget = lib.mkOption { type = lib.types.str; default = "graphical-session.target"; };
    resumeAtLogin = lib.mkEnableOption "resume a previously reviewed, kept CEDAR session at login";
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # No rewriting Hyprland files, no imperative activation hooks, no competing
    # providers disabled. The user must first install/migrate/keep explicitly.
    systemd.user.services.cedar-resume = lib.mkIf cfg.resumeAtLogin {
      Unit = {
        Description = "Resume the approved CEDAR desktop session";
        After = [ cfg.sessionTarget ];
        PartOf = [ cfg.sessionTarget ];
        Requisite = [ cfg.sessionTarget ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/cedar session-login";
        RemainAfterExit = true;
      };
      Install.WantedBy = [ cfg.sessionTarget ];
    };
  };
}
