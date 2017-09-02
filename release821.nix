{ packages ? (_: []), systemPackages ? (_: []) }:

let
  pkgs = import ((import <nixpkgs> {}).fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs-channels";
    rev    = "c9724c6d10b9f15fb3d98ec701724f59880f6cb9";
    sha256 = "06gszir90mafi2w7xxa0h30n2dsc9jlxhcc1rnlvpkn8kxdrl9r0";
  }) {};
  cleanSource = name: type: let
      baseName = baseNameOf (toString name);
      lib = pkgs.lib;
    in !(
      (type == "directory" &&
        (  baseName == ".git"
        || baseName == "dist"
        || baseName == ".stack-work"
      ))                                                          ||
      (type == "symlink"   && (lib.hasPrefix "result" baseName))  ||
      lib.hasSuffix ".hi"    baseName                             ||
      lib.hasSuffix ".ipynb" baseName                             ||
      lib.hasSuffix ".nix"   baseName                             ||
      lib.hasSuffix ".o"     baseName                             ||
      lib.hasSuffix ".sock"  baseName                             ||
      lib.hasSuffix ".yaml"  baseName
    );
  src = builtins.filterSource cleanSource ./.;
  gtk2hs = pkgs.fetchFromGitHub {
    owner  = "gtk2hs";
    repo   = "gtk2hs";
    rev    = "f066503df2c6d8d57e06630615d2097741d09d39";
    sha256 = "1drqwz5ry8i9sv34kkywl5hj0p4yffbjgzb5fgpp4dzdgfxl0cqk";
  };
  plot = pkgs.fetchFromGitHub {
    owner  = "amcphail";
    repo   = "plot";
    rev    = "cc5cdff696aa99e1001124917c3b87b95529c4e3";
    sha256 = "13abrymry4nqyl9gmjrj8lhplbg4xag7x41n89yyw822360d3drh";
  };
  displays = self: builtins.listToAttrs (
    map
      (display: { name = display; value = self.callCabal2nix display "${src}/ihaskell-display/${display}" {}; })
      [
        "ihaskell-aeson"
        "ihaskell-blaze"
        "ihaskell-charts"
        "ihaskell-diagrams"
        "ihaskell-gnuplot"
        "ihaskell-hatex"
        "ihaskell-juicypixels"
        "ihaskell-magic"
        "ihaskell-plot"
        "ihaskell-rlangqq"
        "ihaskell-static-canvas"
        "ihaskell-widgets"
      ]);
  dontCheck = pkgs.haskell.lib.dontCheck;
  stringToReplace   = "setSessionDynFlags\n      flags";
  replacementString = "setSessionDynFlags $ flip gopt_set Opt_BuildDynamicToo\n      flags";
  haskellPackages = pkgs.haskell.packages.ghc821.override {
    overrides = self: super: rec {
      ihaskell       = pkgs.haskell.lib.overrideCabal (
                       self.callCabal2nix "ihaskell"          src                  {}) (_drv: {
        doCheck = false;
        postPatch = ''
          substituteInPlace ./src/IHaskell/Eval/Evaluate.hs --replace \
            '${stringToReplace}' '${replacementString}'
        '';
      });
      ghc-parser        = self.callCabal2nix "ghc-parser"     "${src}/ghc-parser"     {};
      ipython-kernel    = self.callCabal2nix "ghc-parser"     "${src}/ipython-kernel" {};
      quickcheck-instances = pkgs.haskell.lib.doJailbreak super.quickcheck-instances;
      shelly = pkgs.haskell.lib.doJailbreak super.shelly;

      gtk2hs-buildtools = self.callCabal2nix "gtk2hs-buildtools" "${gtk2hs}/tools" {};
      glib              = self.callCabal2nix "glib"              "${gtk2hs}/glib"  {};
      pango             = self.callCabal2nix "pango"             "${gtk2hs}/pango" {};
      cairo             = self.callCabal2nix "cairo"             "${gtk2hs}/cairo" {};
      plot              = self.callCabal2nix "plot"               plot             { inherit cairo pango; };

      Chart            = super.callHackage "Chart" "1.8.2" {};
      Chart-cairo      = super.callHackage "Chart-cairo" "1.8.2" {};
      diagrams         = super.callHackage "diagrams" "1.4" {};
      diagrams-cairo   = super.callHackage "diagrams-cairo" "1.4" {};
      diagrams-lib     = super.callHackage "diagrams-lib" "1.4.1.2" {};
      magic            = super.callHackage "magic" "1.1" {};
      static-canvas    = super.callHackage "static-canvas" "0.2.0.3" {};
      diagrams-contrib = super.callHackage "diagrams-contrib" "1.4.1" {};
      diagrams-core    = super.callHackage "diagrams-core" "1.4.0.1" {};
      diagrams-solve   = super.callHackage "diagrams-solve" "0.1.1" {};
      diagrams-svg     = super.callHackage "diagrams-svg" "1.4.1" {};
      dual-tree        = super.callHackage "dual-tree" "0.2.1" {};
      statestack       = super.callHackage "statestack" "0.2.0.5" {};
      cubicbezier      = super.callHackage "cubicbezier" "0.6.0.4" {};
      mfsolve          = super.callHackage "mfsolve" "0.3.2.0" {};
      svg-builder      = super.callHackage "svg-builder" "0.1.0.2" {};
      fast-math        = super.callHackage "fast-math" "1.0.2" {};
    } // displays self;
  };
  ihaskell = haskellPackages.ihaskell;
  ihaskellEnv = haskellPackages.ghcWithPackages (self: with self; [
    ihaskell
    ihaskell-aeson
    ihaskell-blaze
    # ihaskell-charts
    # ihaskell-diagrams
    ihaskell-gnuplot
    ihaskell-hatex
    ihaskell-juicypixels
    ihaskell-magic
    # ihaskell-plot
    # ihaskell-rlangqq
    # ihaskell-static-canvas
    # ihaskell-widgets
  ] ++ packages self);
  jupyter = pkgs.python3.buildEnv.override {
    extraLibs = with pkgs; [ python3Packages.jupyter python3Packages.notebook ];
  };
  ihaskellSh = pkgs.writeScriptBin "ihaskell-notebook" ''
    #! ${pkgs.stdenv.shell}
    export GHC_PACKAGE_PATH="$(echo ${ihaskellEnv}/lib/*/package.conf.d| tr ' ' ':'):$GHC_PACKAGE_PATH"
    export PATH="${pkgs.stdenv.lib.makeBinPath ([ ihaskell ihaskellEnv jupyter ] ++ systemPackages pkgs)}"
    ${ihaskell}/bin/ihaskell install -l $(${ihaskellEnv}/bin/ghc --print-libdir) && ${jupyter}/bin/jupyter notebook
  '';
  profile = "${ihaskell.pname}-${ihaskell.version}/profile/profile.tar";
in
pkgs.buildEnv {
  name = "ihaskell-with-packages";
  buildInputs = [ pkgs.makeWrapper ];
  paths = [ ihaskellEnv jupyter ];
  postBuild = ''
    ln -s ${ihaskellSh}/bin/ihaskell-notebook $out/bin/
    for prg in $out/bin"/"*;do
      if [[ -f $prg && -x $prg ]]; then
        wrapProgram $prg --set PYTHONPATH "$(echo ${jupyter}/lib/*/site-packages)"
      fi
    done
  '';
}
