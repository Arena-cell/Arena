"""Read-only ELF check for 64-bit native libraries in an APK/AAB.

This does not replace zipalign, bundletool configuration or a 16KB runtime test.
"""
import json
import re
import struct
import sys
import zipfile


def inspect(data):
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] not in (1, 2):
        raise ValueError('Expected a 64-bit ELF library')
    endian = '<' if data[5] == 1 else '>'
    offset = struct.unpack_from(endian + 'Q', data, 32)[0]
    size, count = struct.unpack_from(endian + 'HH', data, 54)
    loads = []
    relro_segments = []
    load_segments = []
    for index in range(count):
        kind, flags, _, address, _, _, memory_size, alignment = struct.unpack_from(
            endian + 'IIQQQQQQ', data, offset + index * size)
        if kind == 1:
            loads.append(alignment)
            load_segments.append((address, address + memory_size, flags))
        if kind == 0x6474E552:
            relro_segments.append((address, address + memory_size))
    # Android permits an unaligned RELRO end when its LOAD contains only
    # RELRO and no other writable LOAD overlaps the rounded protection pages.
    # https://developer.android.com/guide/practices/page-sizes
    relro = []
    for start, end in relro_segments:
        own_load = any(a == start and b == end for a, b, _ in load_segments)
        page_start = start // 16384 * 16384
        page_end = (end + 16383) // 16384 * 16384
        overlap = any(flags & 2 and a < page_end and b > page_start
                      and (a, b) != (start, end)
                      for a, b, flags in load_segments)
        relro.append(end % 16384 == 0 or (own_load and not overlap))
    return {'load_alignments': loads, 'relro_aligned': relro,
            'pass': bool(loads) and all(x >= 16384 for x in loads) and all(relro)}


if __name__ == '__main__':
    with zipfile.ZipFile(sys.argv[1]) as archive:
        results = {name: inspect(archive.read(name)) for name in archive.namelist()
                   if re.search(r'(?:^|/)lib/(arm64-v8a|x86_64)/[^/]+\.so$', name)}
    print(json.dumps({'elf_checks': results, 'packaging_and_runtime': 'NOT_TESTED'}, indent=2))
    sys.exit(0 if results and all(x['pass'] for x in results.values()) else 1)
