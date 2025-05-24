# replit.nix

{ pkgs }: {
  deps = [
    pkgs.bashInteractive
    pkgs.jq
    pkgs.curl
    pkgs.wget
    pkgs.git
    pkgs.tmux
    pkgs.openjdk8
  ];
}