"""Generate RQ4 performance and cost figures."""

import os
from pathlib import Path

_matplotlib_cache_dir = Path(os.environ.get("RUN_ARTIFACT_DIR", "outputs")) / ".matplotlib"
_matplotlib_cache_dir.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_matplotlib_cache_dir))

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

from src.artifacts import get_artifact_dir


CONFIGURATIONS = [
    "Lexical configuration",
    "Semantic configuration",
    "VFFinder reimplementation",
    "Structure-aware configuration",
    "Repository-question-answering configuration",
    "Oracle candidate retrieval",
    "Oracle context",
    "Oracle judgment",
]

SHORT_LABELS = [
    "Lexical",
    "Semantic",
    "VFFinder",
    "Struct.\naware",
    "Repo-QA",
    "Oracle\ncand.",
    "Oracle\nctx.",
    "Oracle\njudge",
]

METRICS = {
    "Hit@5": [0.512, 0.604, 0.438, 0.632, 0.571, 0.701, 0.716, 0.692],
    "Recall@10": [0.428, 0.501, 0.312, 0.574, 0.462, 0.684, 0.702, 0.668],
    "MRR": [0.241, 0.318, 0.205, 0.371, 0.342, 0.420, 0.453, 0.438],
    "MAP": [0.218, 0.286, 0.187, 0.334, 0.301, 0.381, 0.409, 0.397],
    "nDCG": [0.334, 0.425, 0.301, 0.489, 0.452, 0.543, 0.574, 0.556],
    "Precision": [0.142, 0.181, 0.128, 0.248, 0.205, 0.244, 0.271, 0.303],
    "F1": [0.222, 0.279, 0.177, 0.356, 0.302, 0.359, 0.389, 0.417],
    "Tokens": [12.4, 21.9, 0.0, 26.9, 44.2, 27.5, 24.6, 26.9],
    "Calls": [2.1, 4.7, 0.0, 6.0, 9.8, 6.2, 5.5, 6.0],
}

PERF_COLS = ["Hit@5", "Recall@10", "MRR", "MAP", "nDCG", "Precision", "F1"]

FS_SUPTITLE = 17
FS_TITLE = 14
FS_LABEL = 12
FS_TICK = 11
FS_NUM = 10.5
FS_SMALL = 10

PLOT_FILENAMES = [
    "rq4_performance_heatmap.png",
    "rq4_cost_bar.png",
    "rq4_efficiency_scatter.png",
    "rq4_e2e_combined.png",
]


def configure_style() -> None:
    plt.rcParams["font.sans-serif"] = [
        "Times New Roman",
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams["font.size"] = 12
    plt.rcParams["axes.linewidth"] = 0.9
    plt.rcParams["figure.dpi"] = 150
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42


def _clean_spines(ax) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def _save_tight(fig, save_path: Path) -> Path:
    fig.savefig(save_path, dpi=300, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)
    return save_path


def _metric_rows(columns: list[str]) -> list[list[float]]:
    return [[METRICS[column][row] for column in columns] for row in range(len(CONFIGURATIONS))]


def _normalized_rows(columns: list[str]) -> list[list[float]]:
    rows = _metric_rows(columns)
    mins = [min(METRICS[column]) for column in columns]
    maxes = [max(METRICS[column]) for column in columns]
    return [
        [
            (value - mins[col]) / (maxes[col] - mins[col] + 1e-12)
            for col, value in enumerate(row)
        ]
        for row in rows
    ]


def plot_performance_heatmap(save_path: Path) -> Path:
    perf = _metric_rows(PERF_COLS)
    norm = _normalized_rows(PERF_COLS)

    fig, ax = plt.subplots(figsize=(11.2, 3.4))
    im = ax.imshow(norm, aspect="auto", cmap="YlGnBu", vmin=0, vmax=1)

    ax.set_xticks(range(len(PERF_COLS)))
    ax.set_xticklabels(PERF_COLS, fontsize=FS_TICK, fontweight="bold")
    ax.set_yticks(range(len(CONFIGURATIONS)))
    ax.set_yticklabels(SHORT_LABELS, fontsize=FS_TICK)

    for i, row in enumerate(perf):
        for j, value in enumerate(row):
            color = "white" if norm[i][j] > 0.62 else "black"
            ax.text(
                j,
                i,
                f"{value:.3f}",
                ha="center",
                va="center",
                fontsize=FS_NUM,
                fontweight="bold",
                color=color,
            )

    ax.axhline(4.5, color="black", linewidth=1.0, linestyle="--", alpha=0.75)
    ax.set_title(
        "RQ4 End-to-End Performance Across Diagnostic Configurations",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=7,
    )
    ax.tick_params(axis="both", length=0, pad=3)
    for spine in ax.spines.values():
        spine.set_visible(False)

    cbar = fig.colorbar(im, ax=ax, fraction=0.022, pad=0.012)
    cbar.set_label("Normalized score", fontsize=FS_SMALL)
    cbar.ax.tick_params(labelsize=FS_SMALL, length=2)

    fig.subplots_adjust(left=0.105, right=0.985, top=0.88, bottom=0.11)
    return _save_tight(fig, save_path)


def plot_cost_bar(save_path: Path) -> Path:
    x = list(range(len(CONFIGURATIONS)))
    tokens = METRICS["Tokens"]
    calls = METRICS["Calls"]

    fig, ax1 = plt.subplots(figsize=(11.2, 3.35))
    bars = ax1.bar(x, tokens, width=0.62, label="Tokens (k)", alpha=0.88)

    ax1.set_ylabel("Tokens (k)", fontsize=FS_LABEL, fontweight="bold")
    ax1.set_xticks(x)
    ax1.set_xticklabels(SHORT_LABELS, fontsize=FS_SMALL)
    ax1.set_ylim(0, max(tokens) * 1.18)
    ax1.grid(axis="y", linestyle="--", alpha=0.32)
    ax1.tick_params(axis="y", labelsize=FS_TICK)
    ax1.tick_params(axis="x", length=0, pad=3)
    _clean_spines(ax1)

    for bar, value in zip(bars, tokens):
        ax1.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.65,
            f"{value:.1f}",
            ha="center",
            va="bottom",
            fontsize=FS_SMALL,
            fontweight="bold",
        )

    ax2 = ax1.twinx()
    ax2.plot(x, calls, marker="o", markersize=5.5, linewidth=2.2, label="Calls")
    ax2.set_ylabel("Calls", fontsize=FS_LABEL, fontweight="bold")
    ax2.set_ylim(0, max(calls) * 1.20)
    ax2.tick_params(axis="y", labelsize=FS_TICK)
    ax2.spines["top"].set_visible(False)

    for i, value in enumerate(calls):
        offset_y = 10 if value == 0 else -14
        ax2.annotate(
            f"{value:.1f}",
            xy=(i, value),
            xytext=(0, offset_y),
            textcoords="offset points",
            ha="center",
            va="center",
            fontsize=FS_SMALL,
            fontweight="bold",
            bbox=dict(facecolor="white", edgecolor="none", alpha=0.78, pad=0.8),
        )

    ax1.set_title(
        "RQ4 Cost Comparison: Tokens and Calls",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=7,
    )

    lines_1, labels_1 = ax1.get_legend_handles_labels()
    lines_2, labels_2 = ax2.get_legend_handles_labels()
    ax1.legend(
        lines_1 + lines_2,
        labels_1 + labels_2,
        loc="upper left",
        frameon=False,
        fontsize=FS_SMALL,
        ncol=2,
        handlelength=1.5,
        columnspacing=1.0,
    )

    fig.subplots_adjust(left=0.075, right=0.925, top=0.86, bottom=0.16)
    return _save_tight(fig, save_path)


def _annotate_efficiency_labels(ax) -> None:
    label_pos = {
        "Lexical": (13.6, 0.225, "left"),
        "Semantic": (23.0, 0.255, "left"),
        "VFFinder": (1.2, 0.185, "left"),
        "Struct. aware": (29.0, 0.337, "left"),
        "Repo-QA": (41.4, 0.322, "right"),
        "Oracle cand.": (29.0, 0.374, "left"),
        "Oracle ctx.": (23.4, 0.392, "right"),
        "Oracle judge": (28.3, 0.432, "left"),
    }

    for label in SHORT_LABELS:
        key = label.replace("\n", " ")
        tx, ty, ha = label_pos[key]
        ax.text(
            tx,
            ty,
            key,
            ha=ha,
            va="center",
            fontsize=FS_SMALL,
            fontweight="bold",
            bbox=dict(facecolor="white", edgecolor="none", alpha=0.72, pad=0.5),
        )


def plot_efficiency_scatter(save_path: Path) -> Path:
    fig, ax = plt.subplots(figsize=(8.6, 3.7))
    tokens = METRICS["Tokens"]
    calls = METRICS["Calls"]
    f1 = METRICS["F1"]
    ndcg = METRICS["nDCG"]
    sizes = [(value + 0.8) * 78 for value in calls]

    sc = ax.scatter(
        tokens,
        f1,
        s=sizes,
        c=ndcg,
        cmap="YlGnBu",
        edgecolors="black",
        linewidths=0.85,
        alpha=0.92,
    )

    ax.axvline(sum(tokens) / len(tokens), linestyle="--", linewidth=1.0, alpha=0.55)
    ax.axhline(sum(f1) / len(f1), linestyle="--", linewidth=1.0, alpha=0.55)
    _annotate_efficiency_labels(ax)

    ax.set_xlabel("Tokens (k)", fontsize=FS_LABEL, fontweight="bold")
    ax.set_ylabel("F1", fontsize=FS_LABEL, fontweight="bold")
    ax.tick_params(axis="both", labelsize=FS_TICK)
    ax.set_xlim(-2.5, 47.5)
    ax.set_ylim(0.15, 0.445)
    ax.grid(True, linestyle="--", alpha=0.32)
    _clean_spines(ax)
    ax.set_title(
        "RQ4 Efficiency View: F1 vs Tokens",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=7,
    )

    cbar = fig.colorbar(sc, ax=ax, fraction=0.032, pad=0.018)
    cbar.set_label("nDCG", fontsize=FS_SMALL)
    cbar.ax.tick_params(labelsize=FS_SMALL, length=2)

    fig.subplots_adjust(left=0.09, right=0.965, top=0.86, bottom=0.16)
    return _save_tight(fig, save_path)


def plot_combined(save_path: Path) -> Path:
    fig = plt.figure(figsize=(14.2, 6.35))
    gs = GridSpec(
        2,
        2,
        figure=fig,
        height_ratios=[1.00, 0.93],
        width_ratios=[1.08, 1.00],
        hspace=0.39,
        wspace=0.24,
    )

    perf = _metric_rows(PERF_COLS)
    norm = _normalized_rows(PERF_COLS)

    ax_hm = fig.add_subplot(gs[0, :])
    im = ax_hm.imshow(norm, aspect="auto", cmap="YlGnBu", vmin=0, vmax=1)
    ax_hm.set_xticks(range(len(PERF_COLS)))
    ax_hm.set_xticklabels(PERF_COLS, fontsize=FS_TICK, fontweight="bold")
    ax_hm.set_yticks(range(len(CONFIGURATIONS)))
    ax_hm.set_yticklabels(SHORT_LABELS, fontsize=FS_TICK)

    for i, row in enumerate(perf):
        for j, value in enumerate(row):
            color = "white" if norm[i][j] > 0.62 else "black"
            ax_hm.text(
                j,
                i,
                f"{value:.3f}",
                ha="center",
                va="center",
                fontsize=FS_NUM,
                fontweight="bold",
                color=color,
            )

    ax_hm.axhline(4.5, color="black", linewidth=1.0, linestyle="--", alpha=0.75)
    ax_hm.set_title(
        "(a) End-to-End Performance Metrics",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=5,
    )
    ax_hm.tick_params(axis="both", length=0, pad=3)
    for spine in ax_hm.spines.values():
        spine.set_visible(False)

    cbar = fig.colorbar(im, ax=ax_hm, fraction=0.014, pad=0.010)
    cbar.set_label("Normalized score", fontsize=FS_SMALL)
    cbar.ax.tick_params(labelsize=FS_SMALL, length=2)

    ax_cost = fig.add_subplot(gs[1, 0])
    x = list(range(len(CONFIGURATIONS)))
    tokens = METRICS["Tokens"]
    calls = METRICS["Calls"]
    bars = ax_cost.bar(x, tokens, width=0.62, label="Tokens (k)", alpha=0.88)

    ax_cost.set_ylabel("Tokens (k)", fontsize=FS_LABEL, fontweight="bold")
    ax_cost.set_xticks(x)
    ax_cost.set_xticklabels(SHORT_LABELS, fontsize=FS_SMALL)
    ax_cost.set_ylim(0, max(tokens) * 1.22)
    ax_cost.grid(axis="y", linestyle="--", alpha=0.32)
    ax_cost.tick_params(axis="y", labelsize=FS_TICK)
    ax_cost.tick_params(axis="x", length=0, pad=3)
    _clean_spines(ax_cost)

    for bar, value in zip(bars, tokens):
        ax_cost.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.55,
            f"{value:.1f}",
            ha="center",
            va="bottom",
            fontsize=FS_SMALL,
            fontweight="bold",
        )

    ax_calls = ax_cost.twinx()
    ax_calls.plot(x, calls, marker="o", markersize=5.3, linewidth=2.1, label="Calls")
    ax_calls.set_ylabel("Calls", fontsize=FS_LABEL, fontweight="bold")
    ax_calls.set_ylim(0, max(calls) * 1.20)
    ax_calls.tick_params(axis="y", labelsize=FS_TICK)
    ax_calls.spines["top"].set_visible(False)

    for i, value in enumerate(calls):
        offset_y = 10 if value == 0 else -14
        ax_calls.annotate(
            f"{value:.1f}",
            xy=(i, value),
            xytext=(0, offset_y),
            textcoords="offset points",
            ha="center",
            va="center",
            fontsize=FS_SMALL,
            fontweight="bold",
            bbox=dict(facecolor="white", edgecolor="none", alpha=0.78, pad=0.8),
        )

    lines_1, labels_1 = ax_cost.get_legend_handles_labels()
    lines_2, labels_2 = ax_calls.get_legend_handles_labels()
    ax_cost.legend(
        lines_1 + lines_2,
        labels_1 + labels_2,
        loc="upper left",
        frameon=False,
        fontsize=FS_SMALL,
        ncol=2,
        handlelength=1.5,
        columnspacing=1.0,
    )
    ax_cost.set_title(
        "(b) Cost: Tokens and Calls",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=5,
    )

    ax_eff = fig.add_subplot(gs[1, 1])
    f1 = METRICS["F1"]
    ndcg = METRICS["nDCG"]
    sizes = [(value + 0.8) * 78 for value in calls]
    sc = ax_eff.scatter(
        tokens,
        f1,
        s=sizes,
        c=ndcg,
        cmap="YlGnBu",
        edgecolors="black",
        linewidths=0.85,
        alpha=0.92,
    )

    ax_eff.axvline(sum(tokens) / len(tokens), linestyle="--", linewidth=1.0, alpha=0.55)
    ax_eff.axhline(sum(f1) / len(f1), linestyle="--", linewidth=1.0, alpha=0.55)
    _annotate_efficiency_labels(ax_eff)
    ax_eff.set_xlabel("Tokens (k)", fontsize=FS_LABEL, fontweight="bold")
    ax_eff.set_ylabel("F1", fontsize=FS_LABEL, fontweight="bold")
    ax_eff.tick_params(axis="both", labelsize=FS_TICK)
    ax_eff.set_xlim(-2.5, 47.5)
    ax_eff.set_ylim(0.15, 0.445)
    ax_eff.grid(True, linestyle="--", alpha=0.32)
    _clean_spines(ax_eff)
    ax_eff.set_title(
        "(c) Efficiency: F1 vs Tokens",
        fontsize=FS_TITLE,
        fontweight="bold",
        pad=5,
    )

    cbar2 = fig.colorbar(sc, ax=ax_eff, fraction=0.036, pad=0.018)
    cbar2.set_label("nDCG", fontsize=FS_SMALL)
    cbar2.ax.tick_params(labelsize=FS_SMALL, length=2)

    fig.suptitle(
        "RQ4 End-to-End Performance and Cost for Diagnostic Configurations",
        fontsize=FS_SUPTITLE,
        fontweight="bold",
        y=0.985,
    )
    fig.subplots_adjust(left=0.055, right=0.985, top=0.905, bottom=0.095)
    return _save_tight(fig, save_path)


def generate_rq4_plots(output_dir: Path | None = None) -> list[Path]:
    configure_style()
    artifact_dir = output_dir or get_artifact_dir()
    artifact_dir.mkdir(parents=True, exist_ok=True)

    output_paths = [artifact_dir / filename for filename in PLOT_FILENAMES]
    plot_performance_heatmap(output_paths[0])
    plot_cost_bar(output_paths[1])
    plot_efficiency_scatter(output_paths[2])
    plot_combined(output_paths[3])
    return output_paths

def main() -> int:
    output_paths = generate_rq4_plots()
    print("Generated RQ4 plots:")
    for path in output_paths:
        print(path)
    return 0
