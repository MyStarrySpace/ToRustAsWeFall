from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


@dataclass
class WireResult:
    material_index: int
    material_name: str
    base_uri: str
    kind: str
    sidecar_uri: str
    texture_index: int | None


def main() -> int:
    args = _parse_args()
    gltf_path = args.gltf.resolve()
    if not gltf_path.exists():
        print(f"glTF not found: {gltf_path}", file=sys.stderr)
        return 2

    with gltf_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    results = wire_sidecars(
        data,
        gltf_path,
        emissive_suffixes=args.emissive_suffix,
        normal_suffixes=args.normal_suffix,
        emissive_factor=_parse_hex_color(args.emissive_factor),
        emissive_strength=args.emissive_strength,
        normal_scale=args.normal_scale,
        material_filters=args.material or [],
        dry_run=args.dry_run,
    )

    for result in results:
        action = "would wire" if args.dry_run else "wired"
        texture_label = "dry-run" if result.texture_index is None else str(result.texture_index)
        print(
            f"{action}: material {result.material_index} ({result.material_name}) "
            f"{result.kind} -> {result.sidecar_uri} from {result.base_uri}; "
            f"texture {texture_label}"
        )

    if not results:
        print("No material sidecars found.")
        return 1 if args.fail_on_no_changes else 0

    if not args.dry_run:
        with gltf_path.open("w", encoding="utf-8", newline="") as handle:
            json.dump(data, handle, separators=(",", ":"))

    print(
        f"{'Would wire' if args.dry_run else 'Wired'} "
        f"{len(results)} material sidecar(s) in {gltf_path}"
    )
    return 0


def wire_sidecars(
    data: dict[str, Any],
    gltf_path: Path,
    *,
    emissive_suffixes: list[str],
    normal_suffixes: list[str],
    emissive_factor: tuple[int, int, int],
    emissive_strength: float,
    normal_scale: float,
    material_filters: list[str],
    dry_run: bool,
) -> list[WireResult]:
    materials: list[dict[str, Any]] = data.setdefault("materials", [])
    textures: list[dict[str, Any]] = data.setdefault("textures", [])
    images: list[dict[str, Any]] = data.setdefault("images", [])
    filter_set = {value.strip() for value in material_filters if value.strip()}
    results: list[WireResult] = []

    for material_index, material in enumerate(materials):
        material_name = str(material.get("name", f"material_{material_index}"))
        if filter_set and not _material_matches_filter(material_index, material_name, filter_set):
            continue

        base_texture_index = _base_texture_index(material, textures)
        if base_texture_index is None:
            continue

        source_index = textures[base_texture_index].get("source")
        if not isinstance(source_index, int) or source_index < 0 or source_index >= len(images):
            continue

        base_uri = str(images[source_index].get("uri", ""))
        base_path = _resolve_gltf_uri(gltf_path, base_uri)
        if base_path is None or not base_path.exists():
            continue

        emissive_uri = _first_existing_sidecar_uri(base_path, emissive_suffixes)
        if emissive_uri:
            texture_index: int | None = None
            if not dry_run:
                texture_index = _wire_emissive(
                    data,
                    material,
                    images,
                    textures,
                    base_texture_index,
                    base_path,
                    emissive_uri,
                    emissive_factor,
                    emissive_strength,
                )
            results.append(
                WireResult(material_index, material_name, base_uri, "emissive", emissive_uri, texture_index)
            )

        normal_uri = _first_existing_sidecar_uri(base_path, normal_suffixes)
        if normal_uri:
            texture_index = None
            if not dry_run:
                texture_index = _wire_normal(
                    material,
                    images,
                    textures,
                    base_texture_index,
                    base_path,
                    normal_uri,
                    normal_scale,
                )
            results.append(
                WireResult(material_index, material_name, base_uri, "normal", normal_uri, texture_index)
            )

    return results


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Wire existing glTF material sidecar textures by base-texture naming convention."
    )
    parser.add_argument("gltf", type=Path, help="Path to a .gltf file.")
    parser.add_argument(
        "--emissive-suffix",
        action="append",
        default=["_emissive"],
        help="Suffix to search beside each base texture. Default: _emissive. May be repeated.",
    )
    parser.add_argument(
        "--normal-suffix",
        action="append",
        default=["_normals", "_normal"],
        help="Suffix to search beside each base texture. Default: _normals and _normal. May be repeated.",
    )
    parser.add_argument(
        "--emissive-factor",
        default="#ffffff",
        help="Material emissiveFactor tint for wired emissive sidecars. Default: #ffffff.",
    )
    parser.add_argument(
        "--emissive-strength",
        type=float,
        default=1.0,
        help="KHR_materials_emissive_strength value. Default: 1.0.",
    )
    parser.add_argument(
        "--normal-scale",
        type=float,
        default=1.0,
        help="glTF normalTexture scale. Default: 1.0.",
    )
    parser.add_argument(
        "--material",
        action="append",
        help="Limit to a material name or zero-based material index. May be repeated.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report sidecars without editing the glTF.",
    )
    parser.add_argument(
        "--fail-on-no-changes",
        action="store_true",
        help="Return exit code 1 when no sidecars are wired.",
    )
    return parser.parse_args()


def _base_texture_index(material: dict[str, Any], textures: list[dict[str, Any]]) -> int | None:
    base_texture = (
        material.get("pbrMetallicRoughness", {})
        .get("baseColorTexture", {})
        .get("index")
    )
    if not isinstance(base_texture, int) or base_texture < 0 or base_texture >= len(textures):
        return None
    return base_texture


def _first_existing_sidecar_uri(base_path: Path, suffixes: list[str]) -> str | None:
    for suffix in suffixes:
        sidecar_uri = f"{base_path.stem}{suffix}{base_path.suffix}"
        if base_path.with_name(sidecar_uri).exists():
            return sidecar_uri
    return None


def _wire_emissive(
    data: dict[str, Any],
    material: dict[str, Any],
    images: list[dict[str, Any]],
    textures: list[dict[str, Any]],
    base_texture_index: int,
    base_path: Path,
    emissive_uri: str,
    emissive_factor: tuple[int, int, int],
    emissive_strength: float,
) -> int:
    texture_index = _ensure_texture_for_sidecar(
        images,
        textures,
        base_texture_index,
        emissive_uri,
        f"{base_path.stem}_emissive",
    )
    material["emissiveTexture"] = {"index": texture_index}
    material["emissiveFactor"] = _color_to_factor(emissive_factor)
    material_extensions = material.setdefault("extensions", {})
    material_extensions["KHR_materials_emissive_strength"] = {
        "emissiveStrength": emissive_strength
    }
    extensions_used = data.setdefault("extensionsUsed", [])
    if "KHR_materials_emissive_strength" not in extensions_used:
        extensions_used.append("KHR_materials_emissive_strength")
    return texture_index


def _wire_normal(
    material: dict[str, Any],
    images: list[dict[str, Any]],
    textures: list[dict[str, Any]],
    base_texture_index: int,
    base_path: Path,
    normal_uri: str,
    normal_scale: float,
) -> int:
    texture_index = _ensure_texture_for_sidecar(
        images,
        textures,
        base_texture_index,
        normal_uri,
        f"{base_path.stem}_normal",
    )
    material["normalTexture"] = {"index": texture_index, "scale": normal_scale}
    return texture_index


def _ensure_texture_for_sidecar(
    images: list[dict[str, Any]],
    textures: list[dict[str, Any]],
    base_texture_index: int,
    sidecar_uri: str,
    texture_name: str,
) -> int:
    image_index = _ensure_image(images, sidecar_uri)
    return _ensure_texture(textures, image_index, texture_name, base_texture_index)


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


if __name__ == "__main__":
    raise SystemExit(main())
