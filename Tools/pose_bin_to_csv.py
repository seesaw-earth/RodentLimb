#!/usr/bin/env python3
"""Read a RodentLimb pose.bin (1.2.1+) and write the frame-by-frame pose as CSV.

pose.bin layout (little-endian):
  b"RLPS" | uint32 version (1) | uint32 header length | header JSON |
  times float64[n] | box_confidence float32[n] | per keypoint: x float32[n], y float32[n], c float32[n]
Missing keypoints have x = y = -1 and confidence 0. Keypoint order: L_fore_paw, L_hind_paw,
R_fore_paw, R_hind_paw, tail_base, nose, mouth.

Usage: python3 pose_bin_to_csv.py path/to/pose.bin [out.csv]
"""
import json
import struct
import sys
from array import array

KEYPOINTS = ["L_fore_paw", "L_hind_paw", "R_fore_paw", "R_hind_paw", "tail_base", "nose", "mouth"]


def read_pose(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RLPS":
        raise ValueError("not a RodentLimb pose.bin file")
    version, header_len = struct.unpack_from("<II", data, 4)
    if version != 1:
        raise ValueError(f"unsupported version {version}")
    offset = 12
    header = json.loads(data[offset:offset + header_len].decode("utf-8"))
    offset += header_len
    n, k = header["frames"], header["keypoints"]

    def take(typecode, count):
        nonlocal offset
        a = array(typecode)
        size = a.itemsize * count
        a.frombytes(data[offset:offset + size])
        if sys.byteorder != "little":
            a.byteswap()
        offset += size
        return a

    times = take("d", n)
    box = take("f", n)
    kps = [(take("f", n), take("f", n), take("f", n)) for _ in range(k)]
    return header, times, box, kps


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".csv"
    header, times, box, kps = read_pose(src)
    names = KEYPOINTS[:len(kps)]
    with open(dst, "w", encoding="utf-8") as out:
        cols = ["frame", "time_s", "box_confidence"]
        for name in names:
            cols += [f"{name}_x", f"{name}_y", f"{name}_confidence"]
        out.write(",".join(cols) + "\n")
        for i in range(len(times)):
            row = [str(i), f"{times[i]:.4f}", f"{box[i]:.3f}"]
            for x, y, c in kps:
                row += [f"{x[i]:.2f}", f"{y[i]:.2f}"] if x[i] >= 0 else ["", ""]
                row.append(f"{c[i]:.3f}")
            out.write(",".join(row) + "\n")
    print(f"{len(times)} frames, {header['width']}x{header['height']} px, {header['fps']:.2f} fps -> {dst}")


if __name__ == "__main__":
    main()
