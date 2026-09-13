"""Offline schema and semantic checks. These checks do NOT authorize release."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

KIT_ROOT = Path(__file__).resolve().parents[1]


class ContractError(ValueError):
    """A structurally valid document can still violate a cross-file contract."""


class UniqueSafeLoader(yaml.SafeLoader):
    pass


def _unique_mapping(loader: UniqueSafeLoader, node: Any, deep: bool = False) -> dict:
    result: dict = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str):
            raise ContractError("YAML mapping keys must be strings")
        if key in result:
            raise ContractError(f"Duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueSafeLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _unique_mapping)


def _json_pairs(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path: Path) -> Any:
    text = path.read_text(encoding="utf-8")
    if path.suffix in (".yaml", ".yml"):
        return yaml.load(text, Loader=UniqueSafeLoader)
    def reject_constant(value: str) -> Any:
        raise ContractError(f"Non-finite JSON constant: {value}")
    return json.loads(text, object_pairs_hook=_json_pairs, parse_constant=reject_constant)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def validate_document(kind: str, data: Any) -> None:
    schema = load(KIT_ROOT / "schemas" / f"{kind}.schema.json")
    Draft202012Validator.check_schema(schema)
    errors = list(Draft202012Validator(schema).iter_errors(data))
    if errors:
        error = errors[0]
        location = "/" + "/".join(str(p) for p in error.absolute_path)
        raise ContractError(f"{kind}{location}: {error.message}")


def _unique(values: list[Any], label: str) -> None:
    require(len(values) == len(set(values)), f"Duplicate {label}")


def _rect(rect: dict, width: int, height: int, label: str) -> None:
    require(0 <= rect["x0"] < rect["x1"] <= width, f"{label}: invalid x bounds")
    require(0 <= rect["y0"] < rect["y1"] <= height, f"{label}: invalid y bounds")


def board_to_canvas(cell: dict, x: int, y: int) -> tuple[int, int]:
    board, source, scale = cell["board_rect"], cell["source_rect"], cell["scale"]
    require(board["x0"] <= x < board["x1"] and board["y0"] <= y < board["y1"],
            "Point is outside the cell; never clamp it")
    return (source["x0"] + (x - board["x0"]) // scale,
            source["y0"] + (y - board["y0"]) // scale)


def validate_bundle(asset: dict, motion: dict, pack: dict, review: dict,
                    pack_sha256: str, plan: dict | None = None,
                    review_sha256: str | None = None) -> None:
    """Validate supplied data and cross-file relationships, not real image content."""
    for kind, data in (("asset", asset), ("motion", motion), ("review-pack", pack), ("review", review)):
        validate_document(kind, data)
    width, height = asset["canvas"]["width"], asset["canvas"]["height"]
    anchor = asset["canvas"]["anchor"]
    require(0 <= anchor["x"] <= width and 0 <= anchor["y"] <= height, "Anchor outside canvas")
    require(motion["asset_id"] == asset["asset_id"] == pack["asset_id"], "Asset ID mismatch")
    require(motion["motion_id"] == pack["motion_id"], "Motion ID mismatch")
    require(motion["direction"] in asset["directions"], "Direction not allowed by asset")
    require(motion["root_motion"] == asset["runtime"]["root_motion"], "Root motion mismatch")
    frames = motion["frames"]
    count = len(frames)
    require([f["index"] for f in frames] == list(range(count)), "Frame indices must be contiguous and zero-based")
    for event in motion["events"]:
        require(event["frame"] < count, "Event frame out of range")
        require(event["offset_ms"] < frames[event["frame"]]["duration_ms"], "Event offset must be inside its frame")

    all_requirements = asset["requirements"] + motion["requirements"] + asset["runtime"]["requirements"]
    _unique([r["id"] for r in all_requirements], "requirement ID")
    expected = asset["requirements"] + motion["requirements"]
    if pack["stage"] == "runtime":
        expected += asset["runtime"]["requirements"]
        require(pack["bindings"]["runtime_manifest"] is not None, "Runtime stage needs a runtime manifest")
        require(any(im["role"] == "runtime_frame" for im in pack["images"]), "Runtime stage needs actual runtime images")
    require(pack["required_checks"] == expected, "Required checks differ from authoritative specs")

    _unique([im["id"] for im in pack["images"]], "image ID")
    image_map = {im["id"]: im for im in pack["images"]}
    require(any(im["role"] == "reference" for im in pack["images"]), "Reference image missing")
    covered: set[int] = set()
    cell_ids: list[str] = []
    for im in pack["images"]:
        for cell in im["cells"]:
            cell_ids.append(cell["id"])
            sr, br, scale = cell["source_rect"], cell["board_rect"], cell["scale"]
            _rect(sr, width, height, "Source rect")
            _rect(br, im["width"], im["height"], "Board rect")
            require(br["x1"] - br["x0"] == (sr["x1"] - sr["x0"]) * scale, "Horizontal scale mismatch")
            require(br["y1"] - br["y0"] == (sr["y1"] - sr["y0"]) * scale, "Vertical scale mismatch")
            index = cell["frame_index"]
            if cell["subject"] == "reference":
                require(index is None, "Reference cell must not impersonate a candidate frame")
            else:
                require(index is not None and 0 <= index < count, "Cell frame index out of range")
            if (cell["subject"] == "candidate"
                    and im["role"] in ("contact_sheet", "runtime_frame")
                    and sr == {"x0": 0, "y0": 0, "x1": width, "y1": height}):
                covered.add(index)
    _unique(cell_ids, "cell ID")
    require(covered == set(range(count)), "Some full candidate frames are missing from evidence")

    require(review["pack_id"] == pack["pack_id"], "Review pack ID mismatch")
    require(review["pack_sha256"] == pack_sha256, "Review is bound to stale or different pack bytes")
    require(review["candidate_id"] == pack["candidate_id"], "Review candidate ID mismatch")
    require(review["stage"] == pack["stage"], "Review stage mismatch")
    checks = review["checks"]
    _unique([c["criterion_id"] for c in checks], "review criterion")
    require({c["criterion_id"] for c in checks} == {r["id"] for r in expected}, "Missing or unknown review criterion")
    check_map = {c["criterion_id"]: c for c in checks}

    def validate_evidence(ev: dict) -> None:
        require(ev["image_id"] in image_map, "Unknown evidence image ID")
        visible = {c["frame_index"] for c in image_map[ev["image_id"]]["cells"] if c["subject"] == "candidate"}
        require(set(ev["frame_indices"]) <= visible, "Evidence cites a frame absent from that image")
        if ev["region"] is not None:
            _rect(ev["region"], width, height, "Evidence region")

    for check in checks:
        if check["result"] in ("pass", "fail"):
            require(bool(check["evidence"]), "Observable check needs evidence")
        for ev in check["evidence"]:
            validate_evidence(ev)
    _unique([issue["id"] for issue in review["issues"]], "issue ID")
    for issue in review["issues"]:
        require(issue["criterion_id"] in check_map, "Issue has unknown criterion")
        require(check_map[issue["criterion_id"]]["result"] == "fail", "Issue must correspond to a failed check")
        for ev in issue["evidence"]:
            validate_evidence(ev)
    failures = {c["criterion_id"] for c in checks if c["result"] == "fail"}
    require(failures == {i["criterion_id"] for i in review["issues"]}, "Every failed check needs an issue")
    unobserved = {c["criterion_id"] for c in checks if c["result"] == "not_observable"}
    requests = {r["criterion_id"] for r in review["evidence_requests"]}
    require(unobserved == requests, "Evidence requests must cover exactly the unobservable checks")
    blocking = {r["id"] for r in expected if r["blocking"]}
    if blocking & unobserved:
        require(review["verdict"] == "needs_evidence", "Unobservable blocking checks cannot pass")
    elif blocking & failures:
        require(review["verdict"] in ("repair", "reject"), "Blocking failures cannot pass")
    else:
        require(review["verdict"] == "pass", "No blocking failure: record advisory issues without vetoing")

    if plan is not None:
        validate_document("repair-plan", plan)
        require(plan["parent_candidate_id"] == pack["candidate_id"], "Repair parent mismatch")
        require(plan["parent_manifest_sha256"] == pack["bindings"]["candidate_manifest"]["sha256"], "Repair parent hash mismatch")
        require(review_sha256 is not None and plan["source_review_sha256"] == review_sha256, "Repair review hash mismatch")
        require(set(plan["issue_ids"]) <= {i["id"] for i in review["issues"]}, "Repair refers to an unknown issue")
        scope = plan["scope"]
        require(all(i < count for i in scope["frame_indices"]), "Repair frame out of range")
        mask_frames = [m["frame_index"] for m in scope["writable_masks"]]
        _unique(mask_frames, "mask frame")
        require(set(mask_frames) <= set(scope["frame_indices"]), "Mask is outside declared repair frames")
        if scope["pixel_mode"] == "masked":
            require(bool(mask_frames) and set(mask_frames) == set(scope["frame_indices"]), "Masked repair needs one mask per changed frame")
        else:
            require(not mask_frames, "Masks are only valid for masked edits")
        if scope["pixel_mode"] == "none":
            require(not scope["frame_indices"], "Metadata-only edit cannot declare pixel frame changes")
        if plan["operation"]["kind"] == "metadata_patch":
            require(scope["pixel_mode"] == "none", "Metadata patch must not edit pixels")
        if plan["operation"]["kind"] == "regenerate":
            require(scope["pixel_mode"] == "new_candidate", "Regeneration must produce a new candidate")
        allowed_modes = {
            "pixel_patch": {"masked"},
            "provider_edit": {"masked", "full_frames"},
            "metadata_patch": {"none"},
            "spec_change": {"none"},
            "regenerate": {"new_candidate"},
        }
        require(scope["pixel_mode"] in allowed_modes[plan["operation"]["kind"]],
                "Operation and pixel permissions disagree")
        if plan["operation"]["kind"] == "metadata_patch":
            require(bool(scope["allowed_metadata_paths"]), "Metadata edit needs explicit field permissions")
        # A structurally valid plan is a draft. Authorization is a separate host decision.


def verify_references(root: Path, documents: list[Any]) -> list[str]:
    """Check local referenced bytes, paths and fixture markers; never fetch URLs."""
    root = root.resolve()
    errors: list[str] = []
    seen: set[tuple[str, str]] = set()

    def visit(value: Any) -> None:
        if isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, dict):
            if value.get("fixture") is True:
                errors.append("Fixture document cannot be treated as production evidence")
            if isinstance(value.get("path"), str) and isinstance(value.get("sha256"), str):
                name, expected = value["path"], value["sha256"]
                key = (name, expected)
                if key in seen:
                    return
                seen.add(key)
                p = Path(name)
                if p.is_absolute() or ".." in p.parts or "\\" in name:
                    errors.append(f"Unsafe artifact path: {name}")
                    return
                p = (root / p).resolve()
                if not p.is_relative_to(root):
                    errors.append(f"Artifact escapes root: {name}")
                elif not p.is_file():
                    errors.append(f"Missing artifact: {name}")
                elif sha256(p) != expected:
                    errors.append(f"Artifact hash mismatch: {name}")
                elif p.suffix in (".json", ".yaml", ".yml"):
                    try:
                        visit(load(p))
                    except (ValueError, yaml.YAMLError) as exc:
                        errors.append(f"Invalid referenced document {name}: {exc}")
            for item in value.values():
                if isinstance(item, (dict, list)):
                    visit(item)
    for document in documents:
        visit(document)
    return errors
