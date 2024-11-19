#!/bin/bash

#######################################################################################
# Check args

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <SAMPLE_PERCENTAGE> <DEST_DIR> <NUM_DATASETS> [BASE_PATH]"
    exit 1
fi

SAMPLE_PERCENTAGE=$1
DEST_DIR=$2
NUM_DATASETS=$3
BASE_PATH=${4:-"/data/sim/IceCube"}

#######################################################################################
# pre-calculate depth-to-datasets arg for 'find'

# like /data/sim/IceCube/<year>/<generated>/<neutrino-generator>/<dataset_id>
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/22645 -> depth=0
# ex: /data/sim/IceCube/2023/generated/neutrino-generator/ -> depth=1
# ex: /data/sim/IceCube/2023/generated/ -> depth=2
depth_to_datasets=$(python3 -c "
from pathlib import Path
import sys

path = Path(sys.argv[1])
SIM = 'sim'
N_SEGMENTS_BASE_TO_DATASET = 5

try:
    base_index = list(path.parts).index(SIM)
except ValueError:
    raise ValueError(f'Path {path} does not contain the base identifier {SIM}/')
segments_after_base = path_parts[base_index + 1:]

depth = N_SEGMENTS_BASE_TO_DATASET - len(segments_after_base)
if depth < 0:
    raise ValueError(f'Path {path} is too specific; the user can supply up to a dataset dir')
print(depth)
" "$BASE_PATH" 2>&1)

#######################################################################################
# Run!

num_processed=0

# iterate over each dataset using as little memory as possible
find "$BASE_PATH" -mindepth "$depth_to_datasets" -maxdepth "$depth_to_datasets" -type d | while read -r dataset_dir; do

    # Stop processing if the specified number of datasets has been reached
    if [ "$num_processed" -ge "$NUM_DATASETS" ]; then
        break
    fi

    # Has this dataset been processed previously?
    if find "$DEST_DIR" -maxdepth 1 -name "*.histo.hdf5" | read -r; then
        echo "Skipping $dataset_dir, an output file with .histo.hdf5 extension already exists in $DEST_DIR."
        continue
    fi

    # Process the dataset
    echo "Processing dataset: $dataset_dir"
    error_output=$(
        python path/to/your/script.py \
            "$dataset_dir" \
            --sample-percentage "$SAMPLE_PERCENTAGE" \
            --dest-dir "$DEST_DIR" \
            2>&1
    )
    exit_status=$?

    # Check if the subprocess exited with an error
    if [ "$exit_status" -ne 0 ]; then
        if echo "$error_output" | grep -q "HistogramNotFoundError"; then
            echo "Warning: HistogramNotFoundError for $dataset_dir, skipping."
            continue
        else
            echo "Error: Failed to process $dataset_dir" >&2
            echo "$error_output" >&2
            exit 1
        fi
    else
        echo "Successfully processed $dataset_dir"
    fi

    # Increment the counter for processed datasets
    num_processed=$((num_processed + 1))

done

echo "Done."
