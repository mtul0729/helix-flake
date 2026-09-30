# Builds the tree-sitter grammars declared in the helix source's
# languages.toml, pinned to the revisions recorded there. Adapted from
# helix-editor/helix's own grammars.nix; uses builtins.fetchTree, which is
# fine in a flake because every fetch is pinned to a rev.
{
  stdenv,
  lib,
  runCommand,
  helixSrc,
  includeGrammarIf ? _: true,
}:
let
  languagesConfig = builtins.fromTOML (builtins.readFile "${helixSrc}/languages.toml");

  isGitGrammar = grammar:
    builtins.hasAttr "source" grammar
    && builtins.hasAttr "git" grammar.source
    && builtins.hasAttr "rev" grammar.source;
  isGitHubGrammar = grammar: lib.hasPrefix "https://github.com" grammar.source.git;
  toGitHubFetcher = url: let
    match = builtins.match "https://github\\.com/([^/]*)/([^/]*)/?" url;
  in {
    owner = builtins.elemAt match 0;
    repo = builtins.elemAt match 1;
  };

  # If `use-grammars.only` is set, use only those grammars.
  # If `use-grammars.except` is set, use all other grammars.
  # Otherwise use all grammars.
  useGrammar = grammar:
    if languagesConfig ? use-grammars.only
    then builtins.elem grammar.name languagesConfig.use-grammars.only
    else if languagesConfig ? use-grammars.except
    then !(builtins.elem grammar.name languagesConfig.use-grammars.except)
    else true;

  grammarsToUse = builtins.filter useGrammar languagesConfig.grammar;
  gitGrammars = builtins.filter isGitGrammar grammarsToUse;

  buildGrammar = grammar: let
    gh = toGitHubFetcher grammar.source.git;
    sourceGit = builtins.fetchTree {
      type = "git";
      url = grammar.source.git;
      rev = grammar.source.rev;
      ref = grammar.source.ref or "HEAD";
      shallow = true;
    };
    sourceGitHub = builtins.fetchTree {
      type = "github";
      owner = gh.owner;
      repo = gh.repo;
      inherit (grammar.source) rev;
    };
    source =
      if isGitHubGrammar grammar
      then sourceGitHub
      else sourceGit;
  in
    stdenv.mkDerivation {
      # see https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/tools/parsing/tree-sitter/grammar.nix
      pname = "helix-tree-sitter-${grammar.name}";
      version = grammar.source.rev;

      src = source;
      sourceRoot =
        if builtins.hasAttr "subpath" grammar.source
        then "source/${grammar.source.subpath}"
        else "source";

      dontConfigure = true;

      FLAGS = [
        "-Isrc"
        "-g"
        "-O3"
        "-fPIC"
        "-fno-exceptions"
        "-Wl,-z,relro,-z,now"
      ];

      SHARED_LIB = grammar.name + stdenv.hostPlatform.extensions.sharedLibrary;

      buildPhase = ''
        runHook preBuild

        if [[ -e src/scanner.cc ]]; then
          $CXX -c src/scanner.cc -o scanner.o $FLAGS
        elif [[ -e src/scanner.c ]]; then
          $CC -c src/scanner.c -o scanner.o $FLAGS
        fi

        $CC -c src/parser.c -o parser.o $FLAGS
        $CXX -shared -o $SHARED_LIB *.o

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir $out
        mv $SHARED_LIB $out/
        runHook postInstall
      '';

      # Strip fails on darwin: "symbols referenced by indirect symbol table
      # entries that can't be stripped"
      fixupPhase = lib.optionalString stdenv.hostPlatform.isLinux ''
        runHook preFixup
        $STRIP $out/$SHARED_LIB
        runHook postFixup
      '';
    };

  grammarsToBuild = builtins.filter includeGrammarIf gitGrammars;
  builtGrammars =
    builtins.map (grammar: {
      inherit (grammar) name;
      value = buildGrammar grammar;
    })
    grammarsToBuild;

  grammarLinks =
    lib.mapAttrsToList
    (name: artifact: "ln -s ${artifact}/${name}${stdenv.hostPlatform.extensions.sharedLibrary} $out/${name}${stdenv.hostPlatform.extensions.sharedLibrary}")
    (builtins.listToAttrs builtGrammars);
in
  runCommand "consolidated-helix-grammars" {} ''
    mkdir -p $out
    ${builtins.concatStringsSep "\n" grammarLinks}
  ''
