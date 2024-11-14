"""Tests for aggregate_dataset_histos.py"""

import argparse
import json
import pickle
import sys
import tempfile
from pathlib import Path

import h5py  # type: ignore
import pytest

# Add the project root to sys.path
project_root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(project_root))

from scripts.aggregate_dataset_histos import (  # noqa: E402
    _main,
    get_job_histo_files,
    update_aggregation,
)


def test_100__get_job_histo_files_sampling():
    # Create a temporary dataset directory with histogram files
    with tempfile.TemporaryDirectory() as tempdir:
        dataset_dir = Path(tempdir)
        subdir = dataset_dir / "job1/histos"
        subdir.mkdir(parents=True)

        # Create mock histogram files
        for i in range(10):
            (subdir / f"histo_{i}.pkl").touch()

        # Sample 50%
        sampled_files = list(get_job_histo_files(dataset_dir, sample_percentage=0.5))
        assert len(sampled_files) == 5  # Should sample 5 files out of 10

        # Sample 100%
        sampled_files = list(get_job_histo_files(dataset_dir, sample_percentage=1.0))
        assert len(sampled_files) == 10  # Should sample all 10 files

        # Sample 0%
        sampled_files = list(get_job_histo_files(dataset_dir, sample_percentage=0.0))
        assert len(sampled_files) == 0  # Should sample none


def test_200__update_aggregation_matching_histogram():
    existing = {
        "name": "PrimaryEnergy",
        "xmin": 0.0,
        "xmax": 10.0,
        "overflow": 0,
        "underflow": 0,
        "nan_count": 5,
        "bin_values": [1.0, 2.0, 3.0],
        "_sample_count": 1,
    }
    new = {
        "name": "PrimaryEnergy",
        "xmin": 2.0,
        "xmax": 8.0,
        "overflow": 0,
        "underflow": 0,
        "nan_count": 2,
        "bin_values": [0.5, 1.5, 2.5],
    }
    updated = update_aggregation(existing, new)

    # Check the updated values
    assert updated["xmin"] == 0.0  # minimum of both xmin
    assert updated["xmax"] == 10.0  # maximum of both xmax
    assert updated["nan_count"] == 7  # nan_count is summed
    assert updated["bin_values"] == [1.5, 3.5, 5.5]  # bin_values are summed
    assert updated["_sample_count"] == 2  # incremented sample count


def test_210__update_aggregation_histogram_length_mismatch():
    existing = {
        "name": "PrimaryEnergy",
        "xmin": 0.0,
        "xmax": 10.0,
        "overflow": 0,
        "underflow": 0,
        "nan_count": 5,
        "bin_values": [1.0, 2.0],
        "_sample_count": 1,
    }
    new = {
        "name": "PrimaryEnergy",
        "xmin": 2.0,
        "xmax": 8.0,
        "overflow": 0,
        "underflow": 0,
        "nan_count": 2,
        "bin_values": [1.0, 2.0, 3.0],  # different length
    }
    with pytest.raises(
        ValueError,
        match=r"'bin_values' list must have the same length: \[.*?\] \+ \[.*?\]",
    ):
        update_aggregation(existing, new)


def test_300__aggregate_histograms():
    # Mock some sample histograms and an output directory
    sample_histograms = {
        "PrimaryEnergy": {
            "name": "PrimaryEnergy",
            "xmin": 0.0,
            "xmax": 10.0,
            "overflow": 0,
            "underflow": 0,
            "nan_count": 0,
            "bin_values": [10, 20, 30],
        }
    }

    with tempfile.TemporaryDirectory() as tempdir:
        output_dir = Path(tempdir)
        dataset_path = output_dir / "sample_dataset"
        dataset_path.mkdir(parents=True)

        # Save mock histogram to dataset
        histo_file = dataset_path / "histos/0.pkl"
        with open(histo_file, "wb") as f:
            pickle.dump(sample_histograms, f)

        # Prepare args
        args = argparse.Namespace(
            path=dataset_path,
            sample_percentage=1.0,  # sample everything
            dest_dir=output_dir,
        )

        # Run main aggregation
        _main(args=args)

        # Check output JSON and HDF5 files
        json_file = output_dir / "sample_dataset.json"
        assert json_file.exists()
        with open(json_file, "r") as f:
            data = json.load(f)
            print(data)
            assert "PrimaryEnergy" in data
            assert data["PrimaryEnergy"]["bin_values"] == [10, 20, 30]

        hdf5_file = output_dir / "sample_dataset.hdf5"
        assert hdf5_file.exists()
        with h5py.File(hdf5_file, "r") as f:
            assert "PrimaryEnergy" in f
            assert list(f["PrimaryEnergy/bin_values"][:]) == [10, 20, 30]
