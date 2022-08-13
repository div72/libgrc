module serialize

import math

fn test_serialize_compactsize() {
	mut stream := Stream{}
	stream.allocate((int(math.log2(0x02000000)) + 1) * 16)
	for i := u64(1); i <= 0x02000000; i *= 2 {
		stream.write(CompactSize(i - 1))
		stream.write(CompactSize(i))
	}
	before_seek := stream.offset
	min_len := (int(math.log2(0x02000000)) + 1) * 2
	max_len := min_len * 8
	assert stream.offset > min_len
	assert max_len > stream.offset
	stream.seek(0)
	for i := u64(1); i <= 0x02000000; i *= 2 {
		assert stream.read<CompactSize>() == (i - 1)
		assert stream.read<CompactSize>() == i
	}
	assert stream.offset == before_seek  // Check that the stream is depleted
}

fn test_combined() {
	mut stream := Stream{}
	stream.allocate((int(math.log2(0x02000000)) + 1) * 15 + 46)
	for i := u64(1); i <= 0x02000000; i *= 2 {
		stream.write<u8>(u8(i))
		stream.write<i16>(i16(i))
		stream.write<u32>(u32(i))
		stream.write<i64>(i64(i))
	}
	stream.write_padded('the fence.', 15)
	stream.write('The quick brown fox jumps over')
	stream.seek(0)
	for i := u64(1); i <= 0x02000000; i *= 2 {
		assert stream.read<u8>() == u8(i)
		assert stream.read<i16>() == i16(i)
		assert stream.read<u32>() == u32(i)
		assert stream.read<i64>() == i64(i)
	}
	assert stream.read_padded(15) == 'the fence.'
	assert stream.read<string>() == 'The quick brown fox jumps over'

	assert stream.len == stream.offset
}
