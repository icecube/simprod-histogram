#!/bin/bash
set -euo pipefail

#######################################################################################
# This script automates the sampling of histograms from dataset directories. It takes
# a base directory containing simulation datasets, a sample percentage for the histograms,
# and the number of datasets to process. It scans each dataset directory to check for
# existing histogram files and skips any datasets that have already been processed.
#
# Usage:
#   ./sample-each-dataset.sh <BASE_PATH> <SAMPLE_PERCENTAGE> <MAX_NUM_DATASETS>
#
# Arguments:
#   <BASE_PATH>         - The root path under which all dataset directories are located.
#                         Example paths:
#                         /data/sim/IceCube/2023/generated/neutrino-generator/22645
#                         /data/sim/IceCube/2023/generated/neutrino-generator/
#                         /data/sim/IceCube/2023/generated/
#                         /data/sim/IceCube/2023/
#                         /data/sim/IceCube/
#   <SAMPLE_PERCENTAGE> - Percentage of a dataset's histograms to sample
#   <MAX_NUM_DATASETS>      - Number of datasets to process in this run
#
# Requirements:
# - Python 3
#
#######################################################################################

# Check args
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <BASE_PATH> <SAMPLE_PERCENTAGE> <MAX_NUM_DATASETS>"
    exit 1
fi

# set BASE_PATH -> scan all datasets under this path
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/22645
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/
# ex: /data/sim/IceCube/2023/generated/
BASE_PATH=$1

SAMPLE_PERCENTAGE=$2
MAX_NUM_DATASETS=$3

#######################################################################################
# setup python virtual environment, install the package

PYVENV="simprod-histogram-pyvenv"
pip install virtualenv
python -m virtualenv $PYVENV
. $PYVENV/bin/activate &&
    pip install --upgrade pip &&
    pip install --no-cache-dir icecube-simprod-histogram

#######################################################################################
# pre-calculate depth-to-datasets arg for 'find'

# like /data/sim/IceCube/<year>/<generated>/<neutrino-generator>/<dataset_id>
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/22645 -> depth=0
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/ -> depth=1
# ex: /data/sim/IceCube/2023/generated/ -> depth=2
depth_to_datasets=$(python -m simprod_histogram.calc_depth_to_dataset_dirs "$BASE_PATH" 2>&1)

#######################################################################################
# Run!

# Create a temporary file to track errors
error_file=$(mktemp)
echo "0" >"$error_file"
# Create a temporary file to track count
count_file=$(mktemp)
echo "0" >"count_file"
# and rm those files
cleanup() {
    rm -f "$error_file"
    rm -f "$count_file"
}
trap cleanup EXIT
trap cleanup ERR

# other vars
MAX_REACHED_CODE=2

# Define a helper function to process each dataset
process_dataset() {
    local dataset_dir="$1"
    local dest_dir="$dataset_dir"            # put it into the dataset directory
    local num_processed=$(cat "$count_file") # get the count from the file (wouldn't work if parallelized)

    # Stop processing if the specified number of datasets has been reached
    if [ "$num_processed" -ge "$MAX_NUM_DATASETS" ]; then
        return $MAX_REACHED_CODE # Signals to stop processing datasets
    fi

    # Check if this dataset has been processed previously
    if find "$dest_dir" -maxdepth 1 -name "*.histo.hdf5" | read -r; then
        echo "Skipping $dataset_dir, an output file with .histo.hdf5 extension already exists in $dest_dir."
        return 0 # This is okay, proceed to the next dataset
    fi

    # Process the dataset
    echo "Processing dataset: $dataset_dir"
    local error_output
    error_output=$(
        python -m simprod_histogram.sample_dataset \
            "$dataset_dir" \
            --sample-percentage "$SAMPLE_PERCENTAGE" \
            --dest-dir "$dest_dir" \
            2>&1
    )
    local exit_status=$?

    # Handle subprocess exit status
    if [ "$exit_status" -ne 0 ]; then
        if echo "$error_output" | grep -q "HistogramNotFoundError"; then
            echo "Warning: HistogramNotFoundError for $dataset_dir, skipping."
            return 0 # This is okay, proceed to the next dataset
        else
            echo "Error: Failed to process $dataset_dir" >&2
            echo "$error_output" >&2
            echo "1" >"$error_file" # Set error flag in the temporary file
            return 1                # Error! Stop processing datasets
        fi
    else
        echo "Successfully processed $dataset_dir"
        echo "$((num_processed + 1))" >"$count_file"
        return 0 # This is okay, proceed to the next dataset
    fi
}

export -f process_dataset
export SAMPLE_PERCENTAGE MAX_NUM_DATASETS MAX_REACHED_CODE error_file count_file

# Use find with -exec to process each dataset and handle return codes
find "$BASE_PATH" \
    -mindepth "$depth_to_datasets" \
    -maxdepth "$depth_to_datasets" \
    -type d \
    -exec bash -c 'process_dataset "$0"' {} \;

# Check if any errors were flagged
if [ "$(cat "$error_file")" -ne 0 ]; then
    echo "Exiting with error (see above)." >&2
    exit 1
fi

#######################################################################################

echo "Done."
