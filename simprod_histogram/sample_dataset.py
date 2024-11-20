"""Aggregate the dataset's job's histograms by sampling."""

import argparse
import logging
import math
import pickle
import random
from pathlib import Path
from typing import Any, Iterator

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


class HistogramNotFoundError(Exception):
    """Raised when a histogram is not found."""


def _sample_percentage(val: Any) -> float:
    val = float(val)
    if val <= 0.0 or val > 1.0:
        raise ValueError(
            "--sample-percentage must be between 0.0 (exclusive) and 1.0 (inclusive)"
        )
    return val


def get_job_histo_files(dpath: Path, sample_percentage: float) -> Iterator[Path]:
    """Yield a sample of histogram files, each originating from a job."""
    sample_percentage = _sample_percentage(sample_percentage)
    histos_found = False

    # NOTE: we're randomly sampling evenly across all "job-range" subdirectories,
    #         this keeps memory down (iow, going dir-by-dir). However, it does
    #         mean the files are yielded in "job-range" order. This is fine for
    #         aggregating data.

    for subdir in dpath.glob("*/histos"):
        histo_files = list(subdir.glob("*.pkl"))
        random.shuffle(histo_files)  # randomly sample
        if not histos_found and histo_files:  # a neeeeed for speeeeed
            histos_found = True

        sample_size = math.ceil(len(histo_files) * sample_percentage)  # int is floor
        logging.info(
            f"sampling {sample_percentage * 100:.1f}% of histograms in {subdir.name}"
            f"({sample_size}/{len(histo_files)} total)"
        )
        yield from histo_files[:sample_size]

    # did the glob produce any files?
    if not histos_found:
        raise HistogramNotFoundError(f"No histogram files found in {dpath}")


def update_aggregation(existing: dict, new: dict) -> dict:
    """Incorporate the 'new' histogram with the existing aggregated histogram.

    Note: Does not normalize data
    """
    if new["name"] != existing["name"]:
        logging.warning(
            f"new histogram '{new['name']}' does not match existing histogram '{existing['name']}'"
        )

    def new_bin_values():
        if not existing["bin_values"]:
            return new["bin_values"]
        if len(existing["bin_values"]) != len(new["bin_values"]):
            raise ValueError(
                f"'bin_values' list must have the same length: "
                f"{existing['bin_values']} + {new['bin_values']}"
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


def sample_histograms(
    dpath: Path,
    sample_percentage: float,
) -> dict[str, dict]:
    """Assemble the sampled histograms from the dataset."""
    sampled_histos = {
        t: {
            "name": t,
            "xmin": float("inf"),  # any value will replace this one
            "xmax": float("-inf"),  # any value will replace this one
            "overflow": None,
            "underflow": None,
            "nan_count": 0,
            "bin_values": [],
            "_sample_count": 0,
            "_sample_percentage": sample_percentage,
            "_dataset_path": str(dpath.resolve()),
        }
        for t in HISTO_TYPES
    }

    for i, job_file in enumerate(get_job_histo_files(dpath, sample_percentage)):
        with open(job_file, "rb") as f:
            contents = pickle.load(f)
            for histo_type in contents.keys():
                if histo_type in SKIP_KEYS:
                    continue
                elif histo_type not in HISTO_TYPES:
                    logging.warning(f"unknown histogram type: {histo_type}")
                    continue
                # grab data
                sampled_histos[histo_type] = update_aggregation(
                    sampled_histos[histo_type], contents[histo_type]
                )

    # average data
    for histo in sampled_histos.values():
        histo.update(
            {
                "bin_values": [x / histo["_sample_count"] for x in histo["bin_values"]],  # type: ignore
            }
        )

    return sampled_histos


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
        type=_sample_percentage,
        required=True,
        help="the percentage of a dataset's histogram to be sampled (for each type)",
    )
    parser.add_argument(
        "--dest-dir",
        type=Path,
        required=True,
        help="the destination directory to write a file containing the dataset's sampled histograms",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="force writing the output histogram even if it would overwrite an existing one.",
    )
    args = parser.parse_args()

    _main(args)


def _main(args: argparse.Namespace) -> None:
    outfile = args.dest_dir / f"{args.path.name}.histo.hdf5"
    if not args.force and outfile.exists():
        raise FileExistsError(f"{outfile} already exists")

    # aggregate histograms into condensed samples (1 per type)
    sampled_histos = sample_histograms(args.path, args.sample_percentage)

    #
    # write out sampled (averaged) histos
    with h5py.File(outfile, "w") as f:
        for histo_type, histo in sampled_histos.items():
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
