from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Install it with: python -m pip install Pillow"
    ) from exc


@dataclass
class MaterialResult:
    material_index: int
    material_name: str
    source_uri: str
    emissive_uri: str
    matched_pixels: int
    texture_index: int | None


def main() -> int:
    args = _parse_args()
    gltf_path = args.gltf.resolve()
    if not gltf_path.exists():
        print(f"glTF not found: {gltf_path}", file=sys.stderr)
        return 2

    target_colors = [_parse_hex_color(value) for value in args.color]
    emit_color = _parse_hex_color(args.emit_color) if args.emit_color else None

    with gltf_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    results = apply_emissive_masks(
        data,
        gltf_path,
        target_colors,
        tolerance=args.tolerance,
        strength=args.strength,
        suffix=args.suffix,
        material_filters=args.material or [],
        emit_color=emit_color,
        factor_color=_parse_hex_color(args.factor_color),
        dry_run=args.dry_run,
    )

    for result in results:
        target = "would update" if args.dry_run else "updated"
        texture_label = "dry-run" if result.texture_index is None else str(result.texture_index)
        print(
            f"{target}: material {result.material_index} "
            f"({result.material_name}) -> {result.emissive_uri} "
            f"from {result.source_uri}; matched {result.matched_pixels} pixels; "
            f"texture {texture_label}"
        )

    if not results:
        print("No matching pixels found in selected materials.")
        return 1 if args.fail_on_no_matches else 0

    if not args.dry_run:
        with gltf_path.open("w", encoding="utf-8", newline="") as handle:
            json.dump(data, handle, separators=(",", ":"))

    print(
        f"{'Would wire' if args.dry_run else 'Wired'} "
        f"{len(results)} emissive material(s) in {gltf_path}"
    )
    return 0


def apply_emissive_masks(
    data: dict[str, Any],
    gltf_path: Path,
    target_colors: list[tuple[int, int, int]],
    *,
    tolerance: int,
    strength: float,
    suffix: str,
    material_filters: list[str],
    emit_color: tuple[int, int, int] | None,
    factor_color: tuple[int, int, int],
    dry_run: bool,
) -> list[MaterialResult]:
    materials: list[dict[str, Any]] = data.setdefault("materials", [])
    textures: list[dict[str, Any]] = data.setdefault("textures", [])
    images: list[dict[str, Any]] = data.setdefault("images", [])
    results: list[MaterialResult] = []
    filter_set = {value.strip() for value in material_filters if value.strip()}

    for material_index, material in enumerate(materials):
        material_name = str(material.get("name", f"material_{material_index}"))
        if filter_set and not _material_matches_filter(material_index, material_name, filter_set):
            continue

        base_texture = (
            material.get("pbrMetallicRoughness", {})
            .get("baseColorTexture", {})
            .get("index")
        )
        if not isinstance(base_texture, int) or base_texture < 0 or base_texture >= len(textures):
            continue

        source_index = textures[base_texture].get("source")
        if not isinstance(source_index, int) or source_index < 0 or source_index >= len(images):
            continue

        source_uri = str(images[source_index].get("uri", ""))
        source_path = _resolve_gltf_uri(gltf_path, source_uri)
        if source_path is None or not source_path.exists():
            continue

        emissive_uri = f"{source_path.stem}{suffix}.png"
        emissive_path = source_path.with_name(emissive_uri)
        matched_pixels = _write_mask(
            source_path,
            emissive_path,
            target_colors,
            tolerance=tolerance,
            emit_color=emit_color,
            dry_run=dry_run,
        )
        if matched_pixels <= 0:
            continue

        texture_index: int | None = None
        if not dry_run:
            image_index = _ensure_image(images, emissive_uri)
            texture_index = _ensure_texture(textures, image_index, source_path.stem + suffix, base_texture)
            material["emissiveTexture"] = {"index": texture_index}
            material["emissiveFactor"] = _color_to_factor(factor_color)
            material_extensions = material.setdefault("extensions", {})
            material_extensions["KHR_materials_emissive_strength"] = {
                "emissiveStrength": strength
            }
            extensions_used = data.setdefault("extensionsUsed", [])
            if "KHR_materials_emissive_strength" not in extensions_used:
                extensions_used.append("KHR_materials_emissive_strength")

        results.append(
            MaterialResult(
                material_index=material_index,
                material_name=material_name,
                source_uri=source_uri,
                emissive_uri=emissive_uri,
                matched_pixels=matched_pixels,
                texture_index=texture_index,
            )
        )

    return results


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create and wire glTF emissive textures from base-color pixels."
    )
    parser.add_argument("gltf", type=Path, help="Path to a .gltf file.")
    parser.add_argument(
        "--color",
        action="append",
        required=True,
        help="Hex RGB color to make emissive, e.g. #eceddd. May be repeated.",
    )
    parser.add_argument(
        "--emit-color",
        help="Optional hex RGB color to write into the emissive mask. Defaults to each matched source pixel.",
    )
    parser.add_argument(
        "--factor-color",
        default="#ffffff",
        help="Optional hex RGB material emissiveFactor tint. Default: #ffffff.",
    )
    parser.add_argument(
        "--tolerance",
        type=int,
        default=0,
        help="Per-channel match tolerance from 0 to 255. Default: 0 for exact matches.",
    )
    parser.add_argument(
        "--strength",
        type=float,
        default=1.0,
        help="KHR_materials_emissive_strength value to write. Default: 1.0.",
    )
    parser.add_argument(
        "--suffix",
        default="_emissive",
        help="Suffix for generated PNGs. Default: _emissive.",
    )
    parser.add_argument(
        "--material",
        action="append",
        help="Limit to a material name or zero-based material index. May be repeated.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report matches without writing PNGs or editing the glTF.",
    )
    parser.add_argument(
        "--fail-on-no-matches",
        action="store_true",
        help="Return exit code 1 when selected materials contain no matching pixels.",
    )
    return parser.parse_args()


def _parse_hex_color(value: str) -> tuple[int, int, int]:
    raw = value.strip().removeprefix("#")
    if len(raw) != 6:
        raise argparse.ArgumentTypeError(f"Expected #RRGGBB color, got {value!r}")
    try:
        return (int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16))
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Expected #RRGGBB color, got {value!r}") from exc


def _color_to_factor(color: tuple[int, int, int]) -> list[float]:
    return [channel / 255.0 for channel in color]


def _material_matches_filter(index: int, name: str, filters: set[str]) -> bool:
    return str(index) in filters or name in filters


def _resolve_gltf_uri(gltf_path: Path, uri: str) -> Path | None:
    if not uri or uri.startswith("data:"):
        return None
    parsed = urlparse(uri)
    if parsed.scheme and parsed.scheme != "file":
        return None
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return (gltf_path.parent / unquote(uri)).resolve()


def _write_mask(
    source_path: Path,
    output_path: Path,
    target_colors: list[tuple[int, int, int]],
    *,
    tolerance: int,
    emit_color: tuple[int, int, int] | None,
    dry_run: bool,
) -> int:
    tolerance = max(0, min(255, tolerance))
    matched = 0

    with Image.open(source_path) as source:
        rgba = source.convert("RGBA")
        out_pixels: list[tuple[int, int, int, int]] = []
        for r, g, b, a in rgba.getdata():
            if a > 0 and _matches_any((r, g, b), target_colors, tolerance):
                out_r, out_g, out_b = emit_color or (r, g, b)
                out_pixels.append((out_r, out_g, out_b, 255))
                matched += 1
            else:
                out_pixels.append((0, 0, 0, 255))

        if matched > 0 and not dry_run:
            output = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
            output.putdata(out_pixels)
            output.save(output_path)

    return matched


def _matches_any(
    pixel: tuple[int, int, int],
    target_colors: list[tuple[int, int, int]],
    tolerance: int,
) -> bool:
    for target in target_colors:
        if (
            abs(pixel[0] - target[0]) <= tolerance
            and abs(pixel[1] - target[1]) <= tolerance
            and abs(pixel[2] - target[2]) <= tolerance
        ):
            return True
    return False


def _ensure_image(images: list[dict[str, Any]], uri: str) -> int:
    for index, image in enumerate(images):
        if image.get("uri") == uri:
            image["mimeType"] = "image/png"
            return index
    images.append({"mimeType": "image/png", "uri": uri})
    return len(images) - 1


def _ensure_texture(
    textures: list[dict[str, Any]],
    image_index: int,
    texture_name: str,
    base_texture_index: int,
) -> int:
    for index, texture in enumerate(textures):
        if texture.get("name") == texture_name:
            texture["source"] = image_index
            if "sampler" not in texture and 0 <= base_texture_index < len(textures):
                texture["sampler"] = textures[base_texture_index].get("sampler", 0)
            return index

    sampler = textures[base_texture_index].get("sampler", 0)
    textures.append({"sampler": sampler, "source": image_index, "name": texture_name})
    return len(textures) - 1


if __name__ == "__main__":
    raise SystemExit(main())
