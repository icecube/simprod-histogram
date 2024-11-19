"""Tests for sample_dataset_histos.py"""

import argparse
import pickle
import sys
import tempfile
from pathlib import Path

import h5py  # type: ignore
import pytest

# Add the project root to sys.path
project_root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(project_root))

from simprod_histogram.sample_dataset_histos import (  # noqa: E402
    _main,
    get_job_histo_files,
    update_aggregation,
)


def test_100__get_job_histo_files_sampling():
    """Test sampling of histogram files with varying sample percentages."""
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

        # Sample 0% -> error
        with pytest.raises(
            ValueError,
            match=f"Sample size must be greater than or equal to 1 sample_percentage={0.0}.",
        ):
            sampled_files = list(
                get_job_histo_files(dataset_dir, sample_percentage=0.0)
            )


def test_110__get_job_histo_files_no_histograms():
    """Test that FileNotFoundError is raised when no histogram files are found."""
    # Create a temporary dataset directory without any histogram files
    with tempfile.TemporaryDirectory() as tempdir:
        dataset_dir = Path(tempdir)
        subdir = dataset_dir / "job1/histos"
        subdir.mkdir(parents=True)

        # No histogram files are created in this directory structure

        # Expect FileNotFoundError because there are no histogram files
        with pytest.raises(
            FileNotFoundError, match=f"No histogram files found in {dataset_dir}"
        ):
            list(get_job_histo_files(dataset_dir, sample_percentage=0.5))


def test_200__update_aggregation_matching_histogram():
    """Test updating histogram aggregation with matching histogram types."""
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
    """Test that ValueError is raised for bin length mismatch in aggregation."""
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
    """Test aggregation of histograms and output to HDF5 format."""
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
        histo_file = dataset_path / "00000-00001/histos/0.pkl"
        histo_file.parent.mkdir(parents=True)
        with open(histo_file, "wb") as f:
            pickle.dump(sample_histograms, f)

        # Run
        _main(
            args=argparse.Namespace(
                path=dataset_path,
                sample_percentage=1.0,  # sample everything
                dest_dir=output_dir,
                force=False,
            )
        )

        # Check output JSON and HDF5 files
        hdf5_file = output_dir / "sample_dataset.histo.hdf5"
        assert hdf5_file.exists()
        with h5py.File(hdf5_file, "r") as f:
            assert "PrimaryEnergy" in f
            assert list(f["PrimaryEnergy/bin_values"][:]) == [10, 20, 30]


def test_310__aggregate_histograms_with_force():
    """Test aggregation with force flag to overwrite existing HDF5 output."""
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
        histo_file = dataset_path / "00000-00001/histos/0.pkl"
        histo_file.parent.mkdir(parents=True)
        with open(histo_file, "wb") as f:
            pickle.dump(sample_histograms, f)

        # Run main aggregation without --force (file should be created)
        _main(
            args=argparse.Namespace(
                path=dataset_path,
                sample_percentage=1.0,  # sample everything
                dest_dir=output_dir,
                force=False,  # Do not use the force flag
            )
        )

        # Check output HDF5 file
        hdf5_file = output_dir / "sample_dataset.histo.hdf5"
        assert hdf5_file.exists()

        # Modify the sample histograms for a different dataset
        new_sample_histograms = {
            "PrimaryEnergy": {
                "name": "PrimaryEnergy",
                "xmin": 1.0,
                "xmax": 20.0,
                "overflow": 1,
                "underflow": 1,
                "nan_count": 1,
                "bin_values": [100, 200, 300],
            }
        }

        # Overwrite the existing pickled file with new data
        with open(histo_file, "wb") as f:
            pickle.dump(new_sample_histograms, f)

        # Try running again without --force; should raise an error
        with pytest.raises(FileExistsError):
            _main(
                args=argparse.Namespace(
                    path=dataset_path,
                    sample_percentage=1.0,
                    dest_dir=output_dir,
                    force=False,
                )
            )

        # Run again with --force to allow overwrite
        _main(
            args=argparse.Namespace(
                path=dataset_path,
                sample_percentage=1.0,
                dest_dir=output_dir,
                force=True,  # Enable force to overwrite
            )
        )

        # Check that file was overwritten and contains new data
        assert hdf5_file.exists()
        with h5py.File(hdf5_file, "r") as f:
            assert "PrimaryEnergy" in f
            assert list(f["PrimaryEnergy/bin_values"][:]) == [100, 200, 300]
