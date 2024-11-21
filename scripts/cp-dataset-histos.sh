#!/bin/bash
set -euo pipefail

#######################################################################################
# This script automates the copying of histogram files from dataset directories
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
SIM="sim"

# Ensure the destination directory exists
mkdir -p "$DEST_DIR"

#######################################################################################
# Calculate the depth of dataset directories relative to BASE_PATH
depth_to_datasets=$(python -m simprod_histogram.calc_depth_to_dataset_dirs "$BASE_PATH" 2>&1)

#######################################################################################
# Define a function to copy the single histogram file while preserving the directory structure

copy_file() {
    local src_dataset_dir="$1"

    local histo_file="$src_dataset_dir"/*.histo.hdf5
    if [ ! -f "$histo_file" ]; then
        echo "No histogram file found in $src_dataset_dir"
        return
    fi

    # Compute the relative path from 'sim'
    # cp the filetree like:
    #   src_dataset_dir  = '.../sim/IceCube/2023/generated/neutrino-generator/22645'
    #   relative_path    = 'IceCube/2023/generated/neutrino-generator/22645'
    #   dest_dataset_dir = '$DEST_DIR/sim/IceCube/2023/generated/neutrino-generator/22645'
    local relative_path="${src_dataset_dir#"$SIM"/}"
    local dest_dataset_dir="$DEST_DIR/"$SIM"/$relative_path"
    mkdir -p "$dest_dataset_dir"

    # Copy the histogram file(s)
    cp "$histo_file" "$dest_dataset_dir/"
    echo "Copied $histo_file to $dest_dataset_dir"
}

export -f copy_file
export BASE_PATH DEST_DIR SIM

# Use find with -exec to copy files from each dataset
find "$BASE_PATH" \
    -mindepth "$depth_to_datasets" \
    -maxdepth "$depth_to_datasets" \
    -type d \
    -exec bash -c 'copy_file "$0"' {} \;

#######################################################################################

echo "Done."
