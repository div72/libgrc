module cryptography

import crypto.sha256

const hex_digits = {`0`: u8(0), `1`: 1, `2`: 2, `3`: 3, `4`: 4, `5`: 5, `6`: 6, `7`: 7, `8`: 8, `9`: 9, `a`: 10, `b`: 11, `c`: 12, `d`: 13, `e`: 14, `f`: 15}

pub struct Uint256 {
pub mut:
    data [32]u8
}

pub fn double_sha256(data []u8) []u8 {
	return sha256.sum256(sha256.sum256(data))
}

[direct_array_access]
pub fn hash_from_hex(hash_hex string) Uint256 {
	if hash_hex.len != 64 {
		panic('hash_from_hex: invalid input size')
	}

	mut hash := Uint256{}
	for i in 0..32 {
		hash.data[i] = (hex_digits[2 * i] << 4) | hex_digits[2 * i + 1]
	}

	return hash
}
