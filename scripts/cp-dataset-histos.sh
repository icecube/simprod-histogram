#!/bin/bash
set -euo pipefail

#######################################################################################
# This script automates the copying of histogram files from dataset directories
# into a specified destination directory, while preserving the original directory
# structure. For example:
#   BASE_PATH:               '.../sim/IceCube/2023/generated'
#   source dataset dir:      '.../sim/IceCube/2023/generated/neutrino-generator/22645'
#   destination dataset dir: '$DEST_DIR/sim/IceCube/2023/generated/neutrino-generator/22645'
#
# Usage:
#   ./cp-dataset-histos.sh <BASE_PATH> <DEST_DIR> [--force]
#
# Arguments:
#   <BASE_PATH> - The path under which all requested dataset directories are located.
#   <DEST_DIR>  - Destination directory where histogram files will be copied.
#   [--force]   - Optional flag to overwrite existing histogram files in the destination.
#
#######################################################################################

# Check args
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <BASE_PATH> <DEST_DIR> [--force]"
    exit 1
fi

BASE_PATH=$(realpath "$1")
DEST_DIR=$(realpath "$2")
SIM="sim"

# Parse optional --force flag
FORCE=false
for arg in "$@"; do
    if [[ $arg == "--force" ]]; then
        FORCE=true
        break
    fi
done

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
    # dataset directory, they are all copied. Existing files can be overwritten
    # if the --force flag is specified.
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
    local relative_path="${src_dataset_dir#*"$SIM"/}"
    local dest_dataset_dir="$DEST_DIR/$SIM/$relative_path"
    mkdir -p "$dest_dataset_dir"

    # Loop through all matching files and copy them
    local histo_file
    for histo_file in "${histo_files[@]}"; do
        local dest_file="$dest_dataset_dir/$(basename "$histo_file")"
        # check if this overwrites a file
        if [ -f "$dest_file" ]; then
            if [ "$FORCE" == true ]; then
                echo "Overwriting: $dest_file..."
                # cp below
            else
                echo "Histogram file already exists at $dest_dataset_dir (will not overwrite)"
                continue
            fi
        fi
        # cp!
        cp "$histo_file" "$dest_file"
        echo "Copied $histo_file to $dest_dataset_dir"
    done
}

export -f cp_histo
export BASE_PATH DEST_DIR SIM FORCE

# Use find with -exec to copy files from each dataset
find "$BASE_PATH" \
    -mindepth "$depth_to_datasets" \
    -maxdepth "$depth_to_datasets" \
    -type d \
    -exec bash -c 'cp_histo "$0"' {} \;

#######################################################################################

echo "Done."
