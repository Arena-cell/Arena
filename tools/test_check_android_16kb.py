import struct
import unittest

from check_android_16kb import inspect


def elf(headers):
    data = bytearray(64 + 56 * len(headers))
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, len(headers))
    for i, (kind, flags, address, size, alignment) in enumerate(headers):
        struct.pack_into('<IIQQQQQQ', data, 64 + i * 56,
                         kind, flags, 0, address, 0, 0, size, alignment)
    return data


class AlignmentTest(unittest.TestCase):
    def test_android_documented_standalone_relro(self):
        self.assertTrue(inspect(elf([
            (1, 5, 0, 0x680, 0x4000),
            (1, 6, 0x4680, 0x980, 0x4000),
            (0x6474E552, 4, 0x4680, 0x980, 1),
            (1, 6, 0x8000, 0x1000, 0x4000),
        ]))['pass'])

    def test_shared_writable_tail_rejected(self):
        self.assertFalse(inspect(elf([
            (1, 6, 0x4680, 0x3980, 0x4000),
            (0x6474E552, 4, 0x4680, 0x980, 1),
        ]))['pass'])

    def test_other_writable_segment_in_protected_page_rejected(self):
        self.assertFalse(inspect(elf([
            (1, 6, 0x4680, 0x980, 0x4000),
            (0x6474E552, 4, 0x4680, 0x980, 1),
            (1, 6, 0x5000, 0x1000, 0x4000),
        ]))['pass'])

    def test_small_load_alignment_rejected(self):
        self.assertFalse(inspect(elf([(1, 5, 0, 0x1000, 0x1000)]))['pass'])

    def test_aligned_relro(self):
        self.assertTrue(inspect(elf([
            (1, 6, 0x4000, 0x8000, 0x4000),
            (0x6474E552, 4, 0x4000, 0x4000, 1),
        ]))['pass'])


if __name__ == '__main__':
    unittest.main()
