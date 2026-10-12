#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 nurl
"""
Generate grammar information for Helix editor by parsing languages.toml
and fetching source information using nurl in parallel.

Copied from nixpkgs (pkgs/by-name/he/helix/generate_grammars.py). Deliberately
vendored; re-sync manually if upstream fixes bugs. The `_` -> `-` name
conversion here must stay in sync with package.nix's
`lib.removePrefix "tree-sitter-"` lookups.
"""

import argparse
import asyncio
import json
import os
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


@dataclass
class Grammar:
    name: str
    git_url: str
    rev: str
    subpath: str | None = None


def url_parts(grammar: Grammar) -> tuple[str, str]:
    """(owner, repo) of a grammar's git URL."""
    owner, repo = urlparse(grammar.git_url).path.strip("/").split("/")[:2]
    return owner, repo.removesuffix(".git")


# Forges whose fetcher carries no explicit `domain`, because its default already
# points at them. Anything else (self-hosted instances, gitea) records `domain`.
DEFAULT_HOSTS = {
    "fetchFromGitHub": "github.com",
    "fetchFromGitLab": "gitlab.com",
    "fetchFromSourcehut": "git.sr.ht",
}


def entry_is_current(entry: dict[str, Any], grammar: Grammar) -> bool:
    """Whether an entry from a previous run still describes `grammar`.

    A git rev names immutable content, so a match on owner/repo/rev means the
    nurl output would be byte-identical and can be reused; anything else is
    refetched. Note this also carries over nurl *output-format* changes from
    an older nurl version — regenerate with --force if that matters.
    """
    owner, repo = url_parts(grammar)
    nurl = entry.get("nurl", {})
    args = nurl.get("args", {})
    if (args.get("owner"), args.get("repo"), args.get("rev")) != (
        owner,
        repo,
        grammar.rev,
    ):
        return False

    host = args.get("domain") or DEFAULT_HOSTS.get(nurl.get("fetcher", ""))
    return (
        # An unknown host could have produced this entry from a different URL,
        # so refetch instead of trusting it.
        host == urlparse(grammar.git_url).hostname
        and entry.get("subpath") == grammar.subpath
    )


def load_existing(path: Path) -> dict[str, Any]:
    """Entries of a previous run, keyed by grammar name.

    Failed entries are dropped so they get retried.
    """
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}

    return {
        name: entry
        for name, entry in data.items()
        if isinstance(entry, dict) and "error" not in entry and entry.get("nurl")
    }


async def run_nurl(url: str, rev: str, semaphore: asyncio.Semaphore) -> dict[str, Any]:
    """Run nurl command for a single grammar and return parsed JSON output."""
    async with semaphore:
        proc = await asyncio.create_subprocess_exec(
            "nurl",
            url,
            rev,
            "--json",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()

        if proc.returncode != 0:
            raise RuntimeError(f"nurl failed for {url}@{rev}: {stderr.decode()}")

        return json.loads(stdout.decode())


def parse_languages_toml(toml_path: Path) -> list[Grammar]:
    """Parse languages.toml and extract grammar information."""
    with open(toml_path, "rb") as f:
        config = tomllib.load(f)

    grammars = []
    for grammar in config.get("grammar", []):
        if "source" not in grammar:
            continue

        source = grammar["source"]
        if "git" not in source or "rev" not in source:
            continue

        grammars.append(
            Grammar(
                name=grammar["name"].replace("_", "-"),
                git_url=source["git"],
                rev=source["rev"],
                subpath=source.get("subpath"),
            )
        )

    return grammars


async def fetch_all_grammars(
    grammars: list[Grammar], max_parallel: int, existing: dict[str, Any]
) -> dict[str, Any]:
    """Fetch nurl information for all grammars in parallel.

    Grammars already described by `existing` are reused instead of being
    prefetched again, which is every grammar in the common case.
    """
    semaphore = asyncio.Semaphore(max_parallel)
    total = len(grammars)
    results = {}
    pending = []

    for grammar in grammars:
        cached = existing.get(grammar.name)
        if cached is not None and entry_is_current(cached, grammar):
            results[grammar.name] = cached
            continue
        task = run_nurl(grammar.git_url, grammar.rev, semaphore)
        pending.append((grammar, asyncio.create_task(task)))

    reused = total - len(pending)
    if reused:
        print(f"Reusing {reused}/{total} unchanged grammars", file=sys.stderr)

    for grammar, task in pending:
        try:
            result = await task
            results[grammar.name] = {
                "nurl": result,
                "subpath": grammar.subpath,
            }
            print(f"[{len(results)}/{total}] ✓ {grammar.name}", file=sys.stderr)
        except Exception as e:
            print(f"[{len(results)}/{total}] ✗ {grammar.name}: {e}", file=sys.stderr)
            results[grammar.name] = {"error": str(e)}

    # Keep key order that of languages.toml, reused grammars included, so that
    # a run only ever diffs the grammars that actually changed.
    return {grammar.name: results[grammar.name] for grammar in grammars}


async def main():
    parser = argparse.ArgumentParser(
        description="Generate grammar information for Helix editor"
    )
    parser.add_argument(
        "languages_toml",
        type=Path,
        help="path to languages.toml from Helix repository",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("grammars.json"),
        help="output JSON file (default: grammars.json)",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=os.cpu_count(),
        help=f"number of parallel nurl instances (default: {os.cpu_count()})",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="refetch every grammar, ignoring entries of the previous run",
    )

    args = parser.parse_args()

    if not args.languages_toml.exists():
        print(f"Error: {args.languages_toml} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Parsing {args.languages_toml}...", file=sys.stderr)
    grammars = parse_languages_toml(args.languages_toml)
    print(f"Found {len(grammars)} grammars", file=sys.stderr)

    existing = {} if args.force else load_existing(args.output)

    print(f"Fetching grammar information ({args.jobs} parallel jobs)...", file=sys.stderr)
    results = await fetch_all_grammars(grammars, args.jobs, existing)

    errors = [name for name, data in results.items() if "error" in data]
    if errors:
        print(f"\nFailed grammars ({len(errors)}):", file=sys.stderr)
        for name in errors:
            print(f"  - {name}: {results[name]['error']}", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "w") as f:
        json.dump(results, f, indent=2)
        f.write('\n')

    print(f"\nResults written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    asyncio.run(main())
