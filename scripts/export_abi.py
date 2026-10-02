#!/usr/bin/env python3
"""Export or verify the two delivered ABIs using local Forge and Python's standard library."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if an ABI export is missing or differs")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    mismatches = []
    for name in ("LaunchToken", "HackathonRegistry"):
        result = subprocess.run(
            ["forge", "inspect", f"src/{name}.sol:{name}", "abi", "--json"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        abi = json.loads(result.stdout)
        if not isinstance(abi, list):
            raise ValueError(f"Expected an ABI array for {name}")
        output = root / "docs" / "abi" / f"{name}.json"
        content = json.dumps(abi, indent=2) + "\n"
        if args.check:
            if not output.is_file() or output.read_text() != content:
                mismatches.append(str(output.relative_to(root)))
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(content)
            print(f"Exported {output.relative_to(root)}")
    if mismatches:
        raise SystemExit("ABI exports need regeneration: " + ", ".join(mismatches))
    if args.check:
        print("Both ABI exports match the compiled contracts.")


if __name__ == "__main__":
    main()
