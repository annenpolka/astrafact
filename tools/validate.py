#!/usr/bin/env python3
"""Validate the five contract example files. Does not call a model or generator."""
from pathlib import Path
import argparse
import sys
import yaml

from contracts import ContractError, KIT_ROOT, load, sha256, validate_bundle, verify_references


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=KIT_ROOT)
    parser.add_argument("--dir", type=Path, default=Path("examples"))
    parser.add_argument("--verify-artifacts", action="store_true")
    args = parser.parse_args()
    folder = args.dir if args.dir.is_absolute() else args.root / args.dir
    try:
        asset = load(folder / "asset.yaml")
        motion = load(folder / "motion.yaml")
        pack = load(folder / "review-pack.json")
        review = load(folder / "review.json")
        if sha256(folder / "asset.yaml") != pack["bindings"]["asset_spec"]["sha256"]:
            raise ContractError("Asset file bytes differ from the bound spec")
        if sha256(folder / "motion.yaml") != pack["bindings"]["motion_spec"]["sha256"]:
            raise ContractError("Motion file bytes differ from the bound spec")
        plan_path = folder / "repair-plan.json"
        plan = load(plan_path) if plan_path.is_file() else None
        validate_bundle(asset, motion, pack, review,
                        sha256(folder / "review-pack.json"), plan, sha256(folder / "review.json"))
        if args.verify_artifacts:
            errors = verify_references(args.root, [pack, plan])
            if errors:
                raise ContractError("\n".join(errors))
            print("PASS: schema, cross-file contracts, and referenced-file hashes.")
        else:
            print("PASS: schema and cross-file contracts only; image artifacts NOT verified.")
        print("This result is NOT visual approval, runtime approval, or execution authorization.")
        return 0
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
