"""Display the histograms in a file."""

import argparse
import json
import math
import pickle
from pathlib import Path

import h5py  # type: ignore
import matplotlib.pyplot as plt
import numpy as np


def from_hdf5(fpath: Path):
    """Load a non-nested dictionary from an HDF5 file."""
    data_dict = {}

    with h5py.File(fpath) as f:
        for key in f.keys():
            sub_dict = {}

            # Read each dataset within the group
            for sub_key, item in f[key].items():
                if isinstance(item, h5py.Dataset):
                    data = item[()]
                    if isinstance(data, np.ndarray):
                        sub_dict[sub_key] = data.tolist()
                    else:
                        sub_dict[sub_key] = data

            # Read each attribute within the group
            for attr_key, attr_value in f[key].attrs.items():
                # Check if the attribute is NaN, and convert it back to None
                if isinstance(attr_value, float) and np.isnan(attr_value):
                    sub_dict[attr_key] = None
                else:
                    sub_dict[attr_key] = attr_value

            data_dict[key] = sub_dict

    return data_dict


def plot_histograms(histograms, cols=2):
    """Plots multiple histograms in a grid layout with automatic font size adjustment for all text."""
    num_histograms = len(histograms)
    rows = math.ceil(num_histograms / cols)

    # Calculate font sizes based on the grid size
    base_font_size = 12
    font_size = max(6, base_font_size - int(0.4 * (rows * cols - 1)))

    # Adjust figsize to make each plot less tall
    fig, axes = plt.subplots(rows, cols, figsize=(10 * cols, 3 * rows))
    axes = axes.flatten()  # Flatten axes array for easy iteration

    for idx, (name, histo) in enumerate(histograms.items()):
        ax = axes[idx]  # Select the subplot axis
        num_bins = len(histo["bin_values"])

        # Compute x values for the bins
        x_values = [
            histo["xmin"] + (histo["xmax"] - histo["xmin"]) * i / (num_bins - 1)
            for i in range(num_bins)
        ]

        # Plot the histogram
        ax.bar(
            x_values,
            histo["bin_values"],
            width=(histo["xmax"] - histo["xmin"]) / num_bins,
            align="center",
        )

        # Set axis labels, title, and tick label sizes
        ax.set_xlabel("Bins", fontsize=font_size)
        ax.set_ylabel("Values", fontsize=font_size)
        ax.set_title(histo["name"], fontsize=font_size + 2)
        if sub := histo.get("_dataset_path"):
            ax.set_title(f"{histo['name']}\n{sub}", fontsize=font_size)

        # Set tick parameters for both axes
        ax.tick_params(axis="both", labelsize=font_size - 2)

    plt.tight_layout()
    plt.show()


def main():
    """Display them."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "path",
        type=Path,
        help="the path to the histogram file (pickle, json, or hdf5)",
    )
    args = parser.parse_args()

    # get histograms
    if args.path.suffix in [".pickle", ".pkl"]:
        with open(args.path, "rb") as f:
            histograms = pickle.load(f)
    elif args.path.suffix in [".json"]:
        with open(args.path) as f:
            histograms = json.load(f)
    elif args.path.suffix in [".hdf5"]:
        histograms = from_hdf5(args.path)
    else:
        raise RuntimeError(f"Unrecognized file type: {args.path}")

    # display with matplotlib
    plot_histograms(histograms, cols=2)


if __name__ == "__main__":
    main()
