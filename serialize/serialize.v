module serialize

const max_u16 = u64(65535)
const max_u32 = u64(4294967295)

type CompactSize = u64

pub struct Stream {
mut:
	cap int
pub mut:
	data byteptr
	len int
	offset int
}

interface Streamable {
	write(mut stream Stream)
mut:
	read(mut stream Stream) ?
}

pub fn (s1 Stream) == (s2 Stream) bool {
	if s1.len != s2.len {
		return false
	}

	unsafe {
		return C.memcmp(s1.data, s2.data, s1.len) == 0
	}
}

pub fn (mut s Stream) allocate(nbytes int) {
	if nbytes < 1 {
		panic('Stream.allocate: nbytes needs to be positive')
	}
	if nbytes <= s.cap {
	    // No need to allocate if we already have enough.
	    return
	}

	if isnil(s.data) {
		s.data = malloc(nbytes)
	} else {
		s.data = v_realloc(s.data, nbytes)
	}

	s.cap = nbytes
}

pub fn (mut s Stream) free() {
	free(s.data)
	s.len = 0
	s.offset = 0
	s.cap = 0
}

[inline]
pub fn (mut s Stream) seek(offset int) int {
	old_offset := s.offset
	s.offset = offset
	return old_offset
}

[inline]
pub fn (s &Stream) ptr() byteptr {
	unsafe {
		return s.data + s.offset
	}
}

fn typehint_array_read<T>(mut s Stream, elem []T) ?T {
    return s.read<T>()
}

fn typehint_read<T>(mut s Stream, obj T) ?T {
    return s.read<T>()
}

fn workaround_read_compactsize(mut s Stream) ?CompactSize {
    return s.read<CompactSize>()
}

fn workaround_read<U>(mut s Stream) ?U {
    return s.read<U>()
}

fn workaround_push<T>(mut arr []T, elem T) {
    arr << elem
}

// TODO: make optional
pub fn (mut s Stream) read<T>() ?T {
	unsafe {
		$if T is CompactSize {
			ptr := s.ptr()
			s.offset++
			if ptr[0] < 253 {
				return CompactSize(ptr[0])
			}
                        length := 1 << (ptr[0] - 252)
                        if s.offset + length > s.len {
                            return error("out of bounds")
                        }
                        s.offset += length
			match ptr[0] {
				253 {
					return CompactSize(u16(ptr[1]) | (u16(ptr[2]) << 8))
				}
				254 {
					return CompactSize(u32(ptr[1]) | (u32(ptr[2]) << 8) | (u32(ptr[3]) << 16) | (u32(ptr[4]) << 24))
				}
				255 {
					return CompactSize(u64(ptr[1]) | (u64(ptr[2]) << 8) | (u64(ptr[3]) << 16) | (u64(ptr[4]) << 24) | (u64(ptr[5]) << 32) | (u64(ptr[6]) << 40) | (u64(ptr[7]) << 48) | (u64(ptr[8]) << 56))
				}
				else {}
			}
			panic('Stream.read: This should never happen.')
			return CompactSize(0)
		} $else $if T is string {
			size := int(CompactSize(workaround_read_compactsize(mut s)?))
			str_obj := tos(s.ptr(), size).clone()
			s.offset += size
			return str_obj
                //} $else $if T is $Array {
		//	size := int(CompactSize(workaround_read<CompactSize>(mut s)))
                //        mut arr := T{cap: size}
                //        for _ in 0..size {
                //            workaround_push(mut arr, typehint_array_read(mut s, T{}))
                //        }
                //        return arr
                } $else $if T is Streamable {
                    mut obj := T{}
                    obj.read(mut s)?
                    return obj
                //} $else $if T is $Struct {
                //    mut obj := T{}
                //    $for field in T.fields {
                //        obj.$(field.name) = typehint_read(mut s, obj.$(field.name))
                //    }
                //    return obj
		} $else $if T is $Int {
		    obj := &T(s.ptr())
		    s.offset += int(sizeof(T))
		    if s.offset > s.len {
			return error('out of bounds (offset: ${s.offset}, len: ${s.len})')
		    }
		    return *obj
                }
                $else {
                    panic(T{})
                    return T{}
                }
	}

}

pub fn (mut s Stream) read_into(mut dest byteptr, size int) ? {
	if s.offset + size > s.len {
		return error('out of bounds')
	}

	unsafe {
		C.memcpy(dest, s.ptr(), size)
	}
	s.offset += size
}

pub fn (mut s Stream) read_padded(size int) ?string {
	if s.offset + size > s.len {
		return error('out of bounds')
	}

	mut ptr := s.ptr()
	mut real_size := -1
	for i in 0..size {
		unsafe {
			if ptr[i] == 0 {
				real_size = i
				break
			}
		}
	}

	if real_size == -1 {
		real_size = size
	}

	s.offset += size

	unsafe {
		// We clone the string here so the underlying string.str
		// actually points to a C-style NUL terminated string,
		// which may not be the case in our buffer.
		return ptr.vstring_with_len(real_size).clone()
	}
}

pub fn (mut s Stream) write<T>(obj T) {
	unsafe {
		$if T is CompactSize {
			val := u64(obj)
			if val < 253 {
				s.write(u8(val))
			} else if val <= max_u16 {
				s.write(u8(253))
				s.write(u16(val))
			} else if val <= max_u32 {
				s.write(u8(254))
				s.write(u32(val))
			} else {
				s.write(u8(255))
				s.write(val)
			}
			return
		} $else $if T is string {
			s.write<CompactSize>(CompactSize(u64(obj.len)))
			s.write_from(obj.str, obj.len)
			return
                //} $else $if T is $Array {
		//	s.write<CompactSize>(CompactSize(u64(obj.len)))
                //        for idx in 0..obj.len {
                //            s.write(obj[idx])
                //        }
                } $else $if T is Streamable {
                        obj.write(mut s)
                //} $else $if T is $Struct {
                //    $for field in T.fields {
                //        field_value := obj.$(field.name)
                //        s.write(field_value)
                //    }
		} $else $if T is $Int {
		    if s.offset + int(sizeof(T)) > s.cap {
			    s.allocate(int(f64(s.offset + int(sizeof(T))) * 1.5))
		    }

		    C.memcpy(s.ptr(), &obj, sizeof(T))
		    s.len += int(sizeof(T))
		    s.offset += int(sizeof(T))
		    if s.offset > s.len {
		    	    s.len = s.offset
		    }
                } $else {
                    panic(obj)
                }
	}
}

pub fn (mut s Stream) write_padded(src string, size int) {
	if src.len > size {
		panic('Stream.write_padded: input longer than padding')
	}

	if s.offset + size > s.cap {
		s.allocate(int(f64(s.offset + size) * 1.5))
	}

	unsafe {
		C.memset(s.ptr(), 0, size)
		C.memcpy(s.ptr(), src.str, src.len)
	}

	s.offset += size
	if s.offset > s.len {
		s.len = s.offset
	}
}

pub fn (mut s Stream) write_from(src byteptr, size int) {
	if s.offset + size > s.cap {
		s.allocate(int(f64(s.offset + size) * 1.5))
	}

	unsafe {
		C.memcpy(s.ptr(), src, size)
	}

	s.offset += size
	if s.offset > s.len {
		s.len = s.offset
	}
}
