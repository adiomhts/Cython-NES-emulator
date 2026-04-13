from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")

import pygame

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from emulator.nes import NES


PASS_CODE_0_MARKER = "final code of 0 means passed"
PASS_CODE_1_MARKER = "result code of 1 always indicates that all tests were passed"
PASS_CODE_1_MARKER_ALT = "a result code of 1 always indicates that all tests were passed"

SKIP_DIR_NAMES = {"source", "obj", "tools", "recordings", "nsf_singles"}


@dataclass
class SuiteSpec:
    suite_dir: Path
    readme_path: Path
    pass_code: int


@dataclass
class RomResult:
    suite: str
    rom: str
    pass_code: int
    status: str
    result_code: int | None
    reset_requested: bool
    frames: int
    message: str


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def _normalize_suite_root_from_readme(readme: Path) -> Path:
    if readme.parent.name.lower() == "source":
        return readme.parent.parent
    return readme.parent


def _parse_pass_code(readme_text_lower: str) -> int | None:
    if PASS_CODE_0_MARKER in readme_text_lower:
        return 0
    if PASS_CODE_1_MARKER in readme_text_lower or PASS_CODE_1_MARKER_ALT in readme_text_lower:
        return 1
    return None


def discover_suite_specs(root: Path) -> list[SuiteSpec]:
    readmes = list(root.rglob("readme.txt")) + list(root.rglob("README.txt"))
    specs: list[SuiteSpec] = []
    seen: set[Path] = set()

    for readme in readmes:
        text = _read_text(readme)
        text_lower = text.lower()
        if "output at $6000" not in text_lower:
            continue

        pass_code = _parse_pass_code(text_lower)
        if pass_code is None:
            continue

        suite_dir = _normalize_suite_root_from_readme(readme)
        if suite_dir in seen:
            continue

        seen.add(suite_dir)
        specs.append(SuiteSpec(suite_dir=suite_dir, readme_path=readme, pass_code=pass_code))

    specs.sort(key=lambda s: str(s.suite_dir).lower())
    return specs


def discover_roms_for_suite(suite_dir: Path) -> list[Path]:
    roms: list[Path] = []

    for rom in suite_dir.rglob("*.nes"):
        rel_parts = [part.lower() for part in rom.relative_to(suite_dir).parts[:-1]]
        if any(part in SKIP_DIR_NAMES for part in rel_parts):
            continue
        roms.append(rom)

    roms.sort(key=lambda p: str(p).lower())
    return roms


def _mem_u8(nes: NES, address: int) -> int:
    return int(nes.cpu.memory[address]) & 0xFF


def _read_c_string(nes: NES, start: int, max_len: int = 4096) -> str:
    out: list[int] = []
    for offset in range(max_len):
        val = _mem_u8(nes, start + offset)
        if val == 0:
            break
        out.append(val)
    return bytes(out).decode("ascii", errors="replace").strip()


def run_single_rom(
    rom_path: Path,
    max_frames: int,
    max_resets: int,
    reset_delay_frames: int,
) -> tuple[int | None, bool, int, str]:
    nes = NES(str(rom_path))
    reset_requested = False
    reset_count = 0
    reset_countdown = -1
    prev_status = -1

    try:
        for frame_idx in range(1, max_frames + 1):
            nes.run_frame(present=False)

            status = _mem_u8(nes, 0x6000)
            sig_ok = (
                _mem_u8(nes, 0x6001) == 0xDE
                and _mem_u8(nes, 0x6002) == 0xB0
                and _mem_u8(nes, 0x6003) == 0x61
            )
            text = _read_c_string(nes, 0x6004)

            if (
                status == 0x81
                and prev_status != 0x81
                and reset_count < max_resets
                and reset_countdown < 0
            ):
                # Many blargg suites ask for reset with >=100 ms delay.
                reset_countdown = reset_delay_frames

            if reset_countdown >= 0:
                if reset_countdown == 0:
                    nes.cpu.reset()
                    reset_requested = True
                    reset_count += 1
                    reset_countdown = -1
                    prev_status = status
                    continue
                reset_countdown -= 1

            if sig_ok and status < 0x80:
                return status, reset_requested, frame_idx, text

            prev_status = status

        return None, reset_requested, max_frames, _read_c_string(nes, 0x6004)
    finally:
        try:
            nes.shutdown()
        except Exception:
            pass
        pygame.quit()


def run_suites(
    specs: Iterable[SuiteSpec],
    max_frames: int,
    max_resets: int,
    reset_delay_frames: int,
) -> list[RomResult]:
    results: list[RomResult] = []

    for spec in specs:
        roms = discover_roms_for_suite(spec.suite_dir)
        if not roms:
            continue

        for rom in roms:
            try:
                code, reset_req, frames, message = run_single_rom(
                    rom,
                    max_frames=max_frames,
                    max_resets=max_resets,
                    reset_delay_frames=reset_delay_frames,
                )
                if code is None:
                    status = "TIMEOUT"
                elif code == spec.pass_code:
                    status = "PASS"
                else:
                    status = "FAIL"
            except Exception as exc:
                code = None
                reset_req = False
                frames = 0
                message = f"Runner exception: {type(exc).__name__}: {exc}"
                status = "ERROR"

            results.append(
                RomResult(
                    suite=str(spec.suite_dir),
                    rom=str(rom),
                    pass_code=spec.pass_code,
                    status=status,
                    result_code=code,
                    reset_requested=reset_req,
                    frames=frames,
                    message=message,
                )
            )

            print(
                f"[{status}] {rom.relative_to(spec.suite_dir)} "
                f"(suite={spec.suite_dir.name}, expected={spec.pass_code}, got={code}, frames={frames})"
            )

    return results


def summarize(results: list[RomResult]) -> dict[str, int]:
    summary = {"PASS": 0, "FAIL": 0, "TIMEOUT": 0, "ERROR": 0, "TOTAL": 0}
    for item in results:
        summary[item.status] += 1
        summary["TOTAL"] += 1
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run NES test ROM suites with documented $6000 result protocol and "
            "validate against expected pass code from each suite readme."
        )
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent / "nes-test-roms",
        help="Path to tests/nes-test-roms root",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=1200,
        help="Per-ROM timeout in frames",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path(__file__).resolve().parent / "nes_test_report.json",
        help="Output JSON report path",
    )
    parser.add_argument(
        "--suite-filter",
        type=str,
        default="",
        help="Substring filter for suite path",
    )
    parser.add_argument(
        "--max-resets",
        type=int,
        default=3,
        help="Maximum number of reset-button presses for tests that request reset ($6000=$81)",
    )
    parser.add_argument(
        "--reset-delay-frames",
        type=int,
        default=6,
        help="Frames to wait before each requested reset (~6 frames is about 100 ms)",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.exists():
        raise SystemExit(f"Test root not found: {root}")

    specs = discover_suite_specs(root)
    if args.suite_filter:
        needle = args.suite_filter.lower()
        specs = [s for s in specs if needle in str(s.suite_dir).lower()]

    if not specs:
        raise SystemExit("No suite with documented $6000 protocol and pass-code marker found.")

    print(f"Discovered suites: {len(specs)}")
    for spec in specs:
        print(f" - {spec.suite_dir.name}: expected pass code {spec.pass_code}")

    results = run_suites(
        specs=specs,
        max_frames=args.max_frames,
        max_resets=args.max_resets,
        reset_delay_frames=args.reset_delay_frames,
    )
    summary = summarize(results)

    payload = {
        "root": str(root),
        "max_frames": args.max_frames,
        "suite_count": len(specs),
        "summary": summary,
        "results": [asdict(item) for item in results],
    }

    args.report.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\nSummary:")
    print(json.dumps(summary, indent=2))
    print(f"Report: {args.report}")

    return 0 if summary["FAIL"] == 0 and summary["TIMEOUT"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())