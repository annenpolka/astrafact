from __future__ import annotations
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from contracts import (KIT_ROOT, ContractError, board_to_canvas, load,
                       sha256, validate_bundle, verify_references)
from pixel_guard import inspect_patch
from PIL import Image


class ContractsTest(unittest.TestCase):
    def setUp(self):
        folder = KIT_ROOT / "examples"
        self.asset = load(folder / "asset.yaml")
        self.motion = load(folder / "motion.yaml")
        self.pack = load(folder / "review-pack.json")
        self.review = load(folder / "review.json")
        self.plan = load(folder / "repair-plan.json")
        self.pack_hash = sha256(folder / "review-pack.json")
        self.review_hash = sha256(folder / "review.json")

    def check(self):
        validate_bundle(self.asset, self.motion, self.pack, self.review,
                        self.pack_hash, self.plan, self.review_hash)

    def test_example_contracts(self):
        self.check()

    def test_unknown_top_level_field(self):
        self.asset["quality_magic"] = True
        with self.assertRaises(ContractError): self.check()

    def test_one_based_frames_rejected(self):
        for frame in self.motion["frames"]: frame["index"] += 1
        with self.assertRaises(ContractError): self.check()

    def test_event_at_exclusive_frame_end_rejected(self):
        self.motion["events"][0]["offset_ms"] = 50
        with self.assertRaises(ContractError): self.check()

    def test_negative_duration_rejected(self):
        self.motion["frames"][0]["duration_ms"] = -1
        with self.assertRaises(ContractError): self.check()

    def test_unlisted_direction_rejected(self):
        self.motion["direction"] = "N"
        with self.assertRaises(ContractError): self.check()

    def test_asset_id_mismatch(self):
        self.motion["asset_id"] = "other"
        with self.assertRaises(ContractError): self.check()

    def test_anchor_bounds(self):
        self.asset["canvas"]["anchor"]["x"] = 65
        with self.assertRaises(ContractError): self.check()

    def test_missing_frame_in_board(self):
        self.pack["images"][1]["cells"].pop()
        with self.assertRaises(ContractError): self.check()

    def test_invalid_board_scale(self):
        self.pack["images"][1]["cells"][0]["scale"] = 3
        with self.assertRaises(ContractError): self.check()

    def test_duplicate_image_ids(self):
        self.pack["images"][1]["id"] = "ref_e"
        with self.assertRaises(ContractError): self.check()

    def test_no_reference_image(self):
        self.pack["images"][0]["role"] = "crop"
        with self.assertRaises(ContractError): self.check()

    def test_model_cannot_remove_check(self):
        self.review["checks"].pop()
        with self.assertRaises(ContractError): self.check()

    def test_model_cannot_add_check(self):
        extra = copy.deepcopy(self.review["checks"][0])
        extra["criterion_id"] = "invented.criterion"
        self.review["checks"].append(extra)
        with self.assertRaises(ContractError): self.check()

    def test_pack_cannot_downgrade_requirement(self):
        self.pack["required_checks"][0]["blocking"] = False
        with self.assertRaises(ContractError): self.check()

    def test_stale_pack_hash(self):
        self.review["pack_sha256"] = "0" * 64
        with self.assertRaises(ContractError): self.check()

    def test_unobservable_cannot_pass(self):
        self.review["verdict"] = "pass"
        with self.assertRaises(ContractError): self.check()

    def test_failure_cannot_pass(self):
        for c in self.review["checks"]:
            if c["result"] == "not_observable":
                c["result"] = "pass"
                c["evidence"] = copy.deepcopy(self.review["checks"][0]["evidence"])
        self.review["evidence_requests"] = []
        self.review["verdict"] = "pass"
        with self.assertRaises(ContractError): self.check()

    def test_no_evidence_for_pass(self):
        self.review["checks"][0]["evidence"] = []
        with self.assertRaises(ContractError): self.check()

    def test_unknown_image_in_evidence(self):
        self.review["checks"][0]["evidence"][0]["image_id"] = "invisible_image"
        with self.assertRaises(ContractError): self.check()

    def test_evidence_cites_invisible_frame(self):
        self.review["checks"][0]["evidence"][0]["frame_indices"] = [100]
        with self.assertRaises(ContractError): self.check()

    def test_fail_needs_issue(self):
        self.review["issues"] = []
        with self.assertRaises(ContractError): self.check()

    def test_missing_evidence_request(self):
        self.review["evidence_requests"] = []
        with self.assertRaises(ContractError): self.check()

    def test_repair_needs_mask(self):
        self.plan["scope"]["writable_masks"] = []
        with self.assertRaises(ContractError): self.check()

    def test_repair_parent_hash(self):
        self.plan["parent_manifest_sha256"] = "0" * 64
        with self.assertRaises(ContractError): self.check()

    def test_repair_unknown_issue(self):
        self.plan["issue_ids"] = ["invented_issue"]
        with self.assertRaises(ContractError): self.check()

    def test_runtime_missing_manifest(self):
        self.pack["stage"] = self.review["stage"] = "runtime"
        with self.assertRaises(ContractError): self.check()

    def test_board_coordinate_mapping(self):
        cell = self.pack["images"][1]["cells"][0]
        self.assertEqual(board_to_canvas(cell, 32, 80), (0, 0))
        self.assertEqual(board_to_canvas(cell, 287, 335), (63, 63))

    def test_board_outside_not_clamped(self):
        cell = self.pack["images"][1]["cells"][0]
        with self.assertRaises(ContractError): board_to_canvas(cell, 288, 80)

    def test_artifact_verification_rejects_fixture(self):
        errors = verify_references(KIT_ROOT, [self.pack, self.plan])
        self.assertTrue(any("Fixture" in e for e in errors))
        self.assertTrue(any("Missing artifact" in e for e in errors))

    def test_path_traversal(self):
        errors = verify_references(KIT_ROOT, [{"path": "../secret", "sha256": "0" * 64}])
        self.assertTrue(any("Unsafe" in e for e in errors))

    def test_duplicate_yaml_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / "dup.yaml"
            p.write_text("a: 1\na: 2\n")
            with self.assertRaises(ContractError): load(p)

    def test_duplicate_json_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / "dup.json"
            p.write_text('{"a": 1, "a": 2}')
            with self.assertRaises(ContractError): load(p)


class PixelGuardTest(unittest.TestCase):
    def setUp(self):
        self.a = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
        self.b = self.a.copy()
        self.mask = Image.new("L", (4, 4), 0)

    def test_no_changes(self):
        result = inspect_patch(self.a, self.b, self.mask)
        self.assertEqual(result.changed_pixels, 0)
        self.assertTrue(result.allowed)

    def test_authorized_change(self):
        self.b.putpixel((1, 1), (255, 255, 255, 255))
        self.mask.putpixel((1, 1), 255)
        self.assertTrue(inspect_patch(self.a, self.b, self.mask).allowed)

    def test_unauthorized_change(self):
        self.b.putpixel((1, 1), (255, 255, 255, 255))
        result = inspect_patch(self.a, self.b, self.mask)
        self.assertFalse(result.allowed)
        self.assertEqual(result.unauthorized_pixels, 1)

    def test_transparent_rgb_normalized(self):
        self.b.putpixel((1, 1), (255, 100, 100, 0))
        self.assertEqual(inspect_patch(self.a, self.b, self.mask).changed_pixels, 0)

    def test_soft_mask_rejected(self):
        self.mask.putpixel((1, 1), 128)
        with self.assertRaises(ValueError): inspect_patch(self.a, self.b, self.mask)

    def test_size_mismatch_rejected(self):
        with self.assertRaises(ValueError): inspect_patch(self.a, self.b.resize((8, 8)), self.mask)

    def test_rgb_mask_rejected(self):
        with self.assertRaises(ValueError): inspect_patch(self.a, self.b, self.mask.convert("RGB"))


if __name__ == "__main__":
    unittest.main()
