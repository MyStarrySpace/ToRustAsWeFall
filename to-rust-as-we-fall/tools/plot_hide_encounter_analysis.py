from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt


SCENARIO_COLORS = {
    "success": "#2f7d4a",
    "slow_retreat": "#c96b2c",
    "slow_lure2_activation": "#b03a48",
    "slow_exit": "#6a4c93",
}


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python tools/plot_hide_encounter_analysis.py <analysis.json> [out_dir]")
        return 1

    input_path = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else input_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    with input_path.open("r", encoding="utf-8") as handle:
        bundle = json.load(handle)

    _plot_phase_plane(bundle, out_dir / "hide_encounter_phase_plane.png")
    _plot_bifurcation(bundle, out_dir / "hide_encounter_bifurcation.png")
    _plot_monte_carlo(bundle, out_dir / "hide_encounter_monte_carlo.png")

    print(f"Wrote plots to: {out_dir}")
    return 0


def _plot_phase_plane(bundle: dict, output_path: Path) -> None:
    phase_plane = bundle["phase_plane"]
    traces = phase_plane["traces"]
    boundary = phase_plane["switch_manifold"]["points"]
    boundary_distance = [point["distance"] for point in boundary]
    boundary_stamina = [point["stamina"] for point in boundary]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
    for ax, key, title in [
        (axes[0], "retreat_trace", "Retreat Phase Plane"),
        (axes[1], "exit_trace", "Exit Phase Plane"),
    ]:
        ax.plot(boundary_distance, boundary_stamina, color="#222222", linestyle="--", linewidth=1.5, label="run-finish boundary")
        for trace in traces:
            points = trace[key]
            xs = [point["distance_remaining"] for point in points]
            ys = [point["stamina"] for point in points]
            color = SCENARIO_COLORS.get(trace["scenario"], "#4c78a8")
            label = f'{trace["scenario"]} (S0={trace["initial_stamina"]:.0f})'
            ax.plot(xs, ys, color=color, alpha=0.85, linewidth=1.5, label=label)
        ax.set_title(title)
        ax.set_xlabel("Distance Remaining")
        ax.set_ylabel("Stamina")
        ax.grid(alpha=0.25)

    handles, labels = axes[1].get_legend_handles_labels()
    dedup = dict(zip(labels, handles))
    fig.legend(
        dedup.values(),
        dedup.keys(),
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=3,
        fontsize=8,
    )
    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)


def _plot_bifurcation(bundle: dict, output_path: Path) -> None:
    bifurcation = bundle["stamina_bifurcation"]
    samples = bifurcation["samples"]
    stamina = [sample["initial_stamina"] for sample in samples]
    actual = [1 if sample["actual_success"] else 0 for sample in samples]
    closed_form = [1 if sample["closed_form_success"] else 0 for sample in samples]
    exit_margin = [sample["actual_exit_margin"] if sample["actual_exit_margin"] is not None else float("nan") for sample in samples]
    lure1_margin = [sample["actual_lure1_margin"] if sample["actual_lure1_margin"] is not None else float("nan") for sample in samples]

    fig, axes = plt.subplots(2, 1, figsize=(10, 7), constrained_layout=True, sharex=True)

    axes[0].step(stamina, actual, where="mid", color="#2f7d4a", linewidth=2.0, label="actual success")
    axes[0].step(stamina, closed_form, where="mid", color="#1f77b4", linewidth=1.5, linestyle="--", label="closed-form success")
    threshold = bifurcation.get("first_success_stamina", -1.0)
    if threshold >= 0:
        axes[0].axvline(threshold, color="#444444", linestyle=":", linewidth=1.2, label=f"first success @ {threshold:.1f}")
    axes[0].set_ylim(-0.1, 1.1)
    axes[0].set_ylabel("Success")
    axes[0].set_title("Starting-Stamina Bifurcation")
    axes[0].grid(alpha=0.25)
    axes[0].legend(loc="lower right")

    axes[1].plot(stamina, exit_margin, color="#6a4c93", linewidth=1.8, label="actual exit margin")
    axes[1].plot(stamina, lure1_margin, color="#c96b2c", linewidth=1.8, label="actual lure1 margin")
    axes[1].axhline(0.0, color="#222222", linestyle="--", linewidth=1.0)
    axes[1].set_xlabel("Initial Stamina")
    axes[1].set_ylabel("Margin (s)")
    axes[1].grid(alpha=0.25)
    axes[1].legend(loc="lower right")

    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)


def _plot_monte_carlo(bundle: dict, output_path: Path) -> None:
    mc = bundle["monte_carlo"]
    confusion = mc["confusion_matrix"]
    failure_counts = mc["failure_counts"]

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5), constrained_layout=True)

    matrix = [
        [confusion["true_positive"], confusion["false_negative"]],
        [confusion["false_positive"], confusion["true_negative"]],
    ]
    image = axes[0].imshow(matrix, cmap="Blues")
    axes[0].set_xticks([0, 1], ["Predicted Success", "Predicted Fail"])
    axes[0].set_yticks([0, 1], ["Actual Success", "Actual Fail"])
    axes[0].set_title("Closed-Form vs Monte Carlo")
    for row in range(2):
        for col in range(2):
            axes[0].text(col, row, str(matrix[row][col]), ha="center", va="center", color="#111111")
    fig.colorbar(image, ax=axes[0], fraction=0.046, pad=0.04)

    labels = list(failure_counts.keys()) or ["success-only"]
    values = list(failure_counts.values()) or [0]
    axes[1].bar(labels, values, color="#b03a48")
    axes[1].set_title(f'Monte Carlo Failure Modes ({mc["success_rate"]:.1%} success)')
    axes[1].set_ylabel("Trials")
    axes[1].tick_params(axis="x", rotation=20)
    axes[1].grid(axis="y", alpha=0.25)

    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    raise SystemExit(main())
