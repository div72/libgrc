module serialize

[manualfree]
pub fn byteswap(mut dest byteptr, size int) {
	mut reversed := byteptr(malloc(size))
	for i := 0; i < size; i++ {
		reversed[i] = dest[size - i - 1]
	}
	C.memcpy(dest, reversed, size)
	free(reversed)
}