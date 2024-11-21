#!/bin/bash
set -euo pipefail

#######################################################################################
# This script automates the copying of all histogram files from dataset directories
# into a specified destination directory, while preserving the original directory
# structure relative to the provided BASE_PATH.
#
# Usage:
#   ./copy-histograms.sh <BASE_PATH> <DEST_DIR>
#
# Arguments:
#   <BASE_PATH> - The root path under which all dataset directories are located.
#   <DEST_DIR>  - Destination directory where histogram files will be copied.
#
#######################################################################################

# Check args
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <BASE_PATH> <DEST_DIR>"
    exit 1
fi

BASE_PATH=$(realpath "$1")
DEST_DIR=$(realpath "$2")

# Ensure the destination directory exists
mkdir -p "$DEST_DIR"

#######################################################################################
# Calculate the depth of dataset directories relative to BASE_PATH
depth_to_datasets=$(python -m simprod_histogram.calc_depth_to_dataset_dirs "$BASE_PATH" 2>&1)

#######################################################################################
# Define a function to copy files while preserving the directory structure
copy_files() {
    local dataset_dir="$1"

    # Compute the relative path from BASE_PATH
    local relative_path="${dataset_dir#$BASE_PATH/}"

    # Construct the full destination directory path
    local dest_dataset_dir="$DEST_DIR/$relative_path"

    # Ensure the destination directory exists
    mkdir -p "$dest_dataset_dir"

    # Copy all histogram files to the destination, preserving directory structure
    echo "Copying histograms from $dataset_dir to $dest_dataset_dir"
    find "$dataset_dir" -type f -name "*.histo.hdf5" -exec cp {} "$dest_dataset_dir/" \;

    echo "Copied histograms from $dataset_dir to $dest_dataset_dir"
}

export -f copy_files
export BASE_PATH DEST_DIR

# Use find with -exec to copy files from each dataset
find "$BASE_PATH" \
    -mindepth "$depth_to_datasets" \
    -maxdepth "$depth_to_datasets" \
    -type d \
    -exec bash -c 'copy_files "$0"' {} \;

#######################################################################################

echo "Done."
