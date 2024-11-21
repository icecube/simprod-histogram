"""Calculate the filetree depth from dirpath to the dataset directories.

See calculate() below for more info.
"""

import sys
from pathlib import Path


def calculate(dirpath: Path) -> int:
    """
    Calculate the filetree depth from dirpath to the dataset directories.

    Assumes the naming convention:
        .../sim/IceCube/<year>/<generated>/<neutrino-generator>/<dataset_id>

    Examples:
        .../sim/IceCube/2023/generated/neutrino-generator/22645   -> depth=0
        .../sim/IceCube/2023/generated/neutrino-generator/        -> depth=1
        .../sim/IceCube/2023/generated/                           -> depth=2

    Note:
        This does not enforce that the dirpath be rooted at /data/sim, so it
        allows, both:
            1. using 'realpath' (ex: /data/sim/IceCube/... -> /mnt/lfs6/sim/IceCube/...)
            2: running in a testbed directory (ex: /home/eevans/test/data/sim/IceCube/...)
    """
    SIM = "sim"  # as in '/data/sim' (or a local tree '/home/.../sim/...')
    N_SEGMENTS_BASE_TO_DATASET = 5

    try:
        base_index = list(dirpath.parts).index(SIM)
    except ValueError:
        raise ValueError(f"Path {dirpath} does not contain the base identifier {SIM}/")
    segments_after_base = dirpath.parts[base_index + 1 :]

    depth = N_SEGMENTS_BASE_TO_DATASET - len(segments_after_base)
    if depth < 0:
        raise ValueError(
            f"Path {dirpath} is too specific; the user can supply up to a dataset dir"
        )

    return depth


if __name__ == "__main__":
    print(calculate(Path(sys.argv[1])))
