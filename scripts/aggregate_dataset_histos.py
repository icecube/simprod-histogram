"""Aggregate the dataset's job's histograms, by sampling."""

import argparse
import json
import logging
import math
import pickle
import random
from pathlib import Path
from typing import Iterator

import h5py  # type: ignore
import numpy as np

SKIP_KEYS = ["filelist"]
HISTO_TYPES = [
    "PrimaryZenith",
    "PrimaryCosZenith",
    "PrimaryEnergy",
    "PrimaryType",
    "PrimaryMultiplicity",
    "NMu",
    "SecondaryZenith",
    "SecondaryCosZenith",
    "SecondaryEnergy",
    "SecondaryType",
    "CascadeEnergy",
    "MuonLength",
    "TauLength",
    "LogMostEnergeticMuon",
]


def get_job_histo_files(dataset_dir: Path, sample_percentage: float) -> Iterator[Path]:
    """Yield a sample of histogram files, each originating from a job."""
    sample_percentage = max(0.0, min(sample_percentage, 1.0))

    # NOTE: we're randomly sampling evenly across all "job-range" subdirectories,
    #         this keeps memory down (iow, going dir-by-dir). However, it does
    #         mean the files are yielded in "job-range" order. This is fine for
    #         aggregating data.

    for subdir in dataset_dir.glob("*/histos"):
        histo_files = list(subdir.glob("*.pkl"))
        random.shuffle(histo_files)  # randomly sample
        sample_size = math.ceil(len(histo_files) * sample_percentage)  # int is floor
        logging.info(
            f"sampling {sample_percentage * 100:.1f}% of histograms in {subdir.name}"
            f"({sample_size}/{len(histo_files)} total)"
        )
        yield from histo_files[:sample_size]


def update_aggregation(existing: dict, new: dict) -> dict:
    """Incorporate the 'new' histogram with the existing aggregated histogram.

    Note: Does not normalize data
    """
    if new["name"] != existing["name"]:
        logging.warning(
            f"new histogram '{new["name"]}' does not match existing histogram '{existing['name']}'"
        )

    def new_bin_values():
        if not existing["bin_values"]:
            return new["bin_values"]
        if len(existing["bin_values"]) != len(new["bin_values"]):
            raise ValueError(
                f"'bin_values' list must have the same length: "
                f"{existing["bin_values"]} + {new["bin_values"]}"
            )
        return [a + b for a, b in zip(existing["bin_values"], new["bin_values"])]

    existing.update(
        {
            "xmin": min(existing["xmin"], new["xmin"]),
            "xmax": max(existing["xmax"], new["xmax"]),
            "overflow": None,  # TOD0
            "underflow": None,  # TOD0
            "nan_count": existing["nan_count"] + new["nan_count"],
            "bin_values": new_bin_values(),
            "_sample_count": existing["_sample_count"] + 1,
        }
    )

    return existing


def main() -> None:
    """Do main."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "path",
        type=Path,
        help="the dataset directory to grab pickled histograms",
    )
    parser.add_argument(
        "--sample-percentage",
        type=float,
        required=True,
        help="the percentage of a dataset's histogram to be sampled (for each type)",
    )
    parser.add_argument(
        "--dest-dir",
        type=Path,
        required=True,
        help="the destination directory to write a json file containing aggregated histograms",
    )
    args = parser.parse_args()

    _main(args)


def _main(args: argparse.Namespace) -> None:
    agg_histograms = {
        t: {
            "name": t,
            "xmin": float("inf"),  # any value will replace this one
            "xmax": float("-inf"),  # any value will replace this one
            "overflow": None,
            "underflow": None,
            "nan_count": 0,
            "bin_values": [],
            "_sample_count": 0,
            "_dataset_path": str(args.path.resolve()),
        }
        for t in HISTO_TYPES
    }

    # build aggregated histograms
    for job_file in get_job_histo_files(args.path, args.sample_percentage):
        with open(job_file, "rb") as f:
            contents = pickle.load(f)
            for histo_type in contents.keys():
                if histo_type in SKIP_KEYS:
                    continue
                elif histo_type not in HISTO_TYPES:
                    logging.warning(f"unknown histogram type: {histo_type}")
                    continue
                # grab data
                agg_histograms[histo_type] = update_aggregation(
                    agg_histograms[histo_type], contents[histo_type]
                )

    # average data
    for histo in agg_histograms.values():
        histo.update(
            {
                "bin_values": [x / histo["_sample_count"] for x in histo["bin_values"]],  # type: ignore
            }
        )

    #
    # write out aggregated-averaged histos
    # -> json
    with open(args.dest_dir / f"{args.path.name}.json", "w") as f:
        json.dump(agg_histograms, f)  # don't indent
    # -> hdf5
    with h5py.File(args.dest_dir / f"{args.path.name}.hdf5", "w") as f:
        for histo_type, histo in agg_histograms.items():
            group = f.create_group(histo_type)
            for k, v in histo.items():
                if isinstance(v, list):
                    group.create_dataset(k, data=np.array(v))
                elif v is None:
                    group.attrs[k] = np.nan
                else:
                    group.attrs[k] = v


if __name__ == "__main__":
    main()
