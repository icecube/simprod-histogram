#!/bin/bash
set -euo pipefail

#######################################################################################
# This script automates the copying of histogram files from dataset directories
# into a specified destination directory, while preserving the original directory
# structure, like:
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
# Copy!

cp_histo() {
    # Copies all histogram files (*.histo.hdf5) from a given dataset directory
    # to a destination directory, preserving the directory structure relative
    # to a specified base path (SIM). If multiple histogram files exist in the
    # dataset directory, they are all copied.
    local src_dataset_dir="$1"

    # Check for histo files
    local histo_files=("$src_dataset_dir"/*.histo.hdf5)
    if [ ! -e "${histo_files[0]}" ]; then
        echo "No histogram file found in $src_dataset_dir"
        return
    fi

    # Compute the relative path from 'sim'
    # cp the file tree like:
    #   src_dataset_dir  = '.../sim/IceCube/2023/generated/neutrino-generator/22645'
    #   relative_path    = 'IceCube/2023/generated/neutrino-generator/22645'
    #   dest_dataset_dir = '$DEST_DIR/sim/IceCube/2023/generated/neutrino-generator/22645'
    local relative_path="${src_dataset_dir#"$SIM"/}"
    local dest_dataset_dir="$DEST_DIR/$SIM/$relative_path"
    mkdir -p "$dest_dataset_dir"

    # Loop through all matching files and copy them
    local histo_file
    for histo_file in "${histo_files[@]}"; do
        if [ -f "$dest_dataset_dir/$(basename "$histo_file")" ]; then
            echo "Histogram file already exists at $dest_dataset_dir (will not overwrite)"
        else
            cp "$histo_file" "$dest_dataset_dir/"
            echo "Copied $histo_file to $dest_dataset_dir"
        fi
    done
}

export -f copy_histo_file
export BASE_PATH DEST_DIR SIM

# Use find with -exec to copy files from each dataset
find "$BASE_PATH" \
    -mindepth "$depth_to_datasets" \
    -maxdepth "$depth_to_datasets" \
    -type d \
    -exec bash -c 'cp_histo "$0"' {} \;

#######################################################################################

echo "Done."
