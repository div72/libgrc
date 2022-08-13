module network

import time

import cryptography
import serialize
import util

pub fn calculate_checksum(message serialize.Streamable) []u8 {
	mut stream := serialize.Stream{}
	message.write(mut stream)
	unsafe {
		return cryptography.double_sha256(stream.data.vbytes(stream.offset))
	}
}

pub struct MessageHeader {
pub mut:
	magic [4]u8
	command string // len: 12
	length u32
	checksum [4]u8
}

pub fn (mut header MessageHeader) read(mut stream serialize.Stream) {
	stream.read_into(mut &header.magic, 4)
	header.command = stream.read_padded(12)
	header.length = stream.read<u32>()
	stream.read_into(mut &header.checksum, 4)
}

pub fn (header MessageHeader) write(mut stream serialize.Stream) {
	stream.write_from(&header.magic, 4)
	stream.write_padded(header.command, 12)
	stream.write(header.length)
	stream.write_from(&header.checksum, 4)
}

pub struct Address {
pub mut:
	time u32
	services u64
	ip [16]u8 = [u8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	port u16
}

pub fn (mut addr Address) read(mut stream serialize.Stream) {
	if !false {
		addr.time = stream.read<u32>()
	}
	addr.services = stream.read<u64>()
	unsafe {
		stream.read_into(mut &addr.ip, 16)
		addr.port = stream.read<u16>()
		//serialize.byteswap(&addr.ip, int(sizeof(addr.ip)))
		//serialize.byteswap(mut &addr.port, int(sizeof(addr.port)))
	}
}

pub fn (addr Address) write(mut stream serialize.Stream) {
	stream.write(addr.time)
	stream.write(addr.services)
	ip := [16]u8{}
	C.memcpy(&ip, &addr.ip, 16)
	port := addr.port
	unsafe {
		serialize.byteswap(mut &ip, int(sizeof(ip)))
		serialize.byteswap(mut &port, int(sizeof(port)))
	}
	stream.write_from(&addr.ip, 16)
	stream.write(addr.port)
}

pub struct VersionMessage {
pub mut:
	version int = protocol_version
	services u64 = 1
	timestamp i64 = i64(time.utc().unix)
	addr_recv Address
	addr_from Address
	nonce u64
	user_agent string = "/div72s-experimental-node:0.0.0/"
	start_height int
}

pub fn (mut msg VersionMessage) read(mut stream serialize.Stream) {
	msg.version = stream.read<int>()
	msg.services = stream.read<u64>()
	msg.timestamp = stream.read<i64>()
	msg.addr_recv.read(mut stream)
	msg.addr_from.read(mut stream)
	msg.nonce = stream.read<u64>()
	msg.user_agent = stream.read<string>()
	msg.start_height = stream.read<int>()
}

pub fn (msg VersionMessage) write(mut stream serialize.Stream) {
	stream.write(msg.version)
	stream.write(msg.services)
	stream.write(msg.timestamp)
	msg.addr_recv.write(mut stream)
	msg.addr_from.write(mut stream)
	stream.write(msg.nonce)
	stream.write(msg.user_agent)
	stream.write(msg.start_height)
}

pub struct Verack {
}

pub fn (mut msg Verack) read(mut stream serialize.Stream) {}

pub fn (msg Verack) write(mut stream serialize.Stream) {}

pub struct Ping {
pub mut:
	nonce u64
}

pub fn (mut msg Ping) read(mut stream serialize.Stream) {
	msg.nonce = stream.read<u64>()
}

pub fn (msg Ping) write(mut stream serialize.Stream) {
	stream.write(msg.nonce)
}

pub struct Pong {
pub mut:
	nonce u64
}

pub fn (mut msg Pong) read(mut stream serialize.Stream) {
	msg.nonce = stream.read<u64>()
}

pub fn (msg Pong) write(mut stream serialize.Stream) {
	stream.write(msg.nonce)
}

pub struct GetAddr {}

pub fn (mut msg GetAddr) read(mut stream serialize.Stream) {
}

pub fn (msg GetAddr) write(mut stream serialize.Stream) {
}

pub struct Addr {
pub mut:
    list []Address
}

pub fn (mut msg Addr) read(mut stream serialize.Stream) {
        size := u64(stream.read<serialize.CompactSize>())
        for _ in 0 .. size {
            msg.list << stream.read<Address>()
        }
}

pub fn (msg Addr) write(mut stream serialize.Stream) {
        stream.write<serialize.CompactSize>(u32(msg.list.len))
        for elem in msg.list {
	    stream.write(elem)
        }
}

type Payload = VersionMessage | Verack | Ping | Pong | GetAddr | Addr

pub fn payload_eq(payload1 Payload, payload2 Payload) bool {
	if payload1 is VersionMessage && payload2 is VersionMessage {
		return (payload1 as VersionMessage) == (payload2 as VersionMessage)
	} else if payload1 is Verack && payload2 is Verack {
		return true // verack has no fields, no need to compare
	}
	return false
}

pub fn (mut payload Payload) read(mut stream serialize.Stream) {
	// 2021-01-31: Smart cast doesn't work here, cast everything manually.
	//             Weirdly, it works in the function below.
	match payload {
		VersionMessage {
			mut payload_ := payload as VersionMessage
			payload_.read(mut stream)
		}
		Verack {
			mut payload_ := payload as Verack
			payload.read(mut stream)
		}
		Ping {
			mut payload_ := payload as Ping
			payload_.read(mut stream)
		}
		Pong {
			mut payload_ := payload as Pong
			payload_.read(mut stream)
		}
                GetAddr {
			mut payload_ := stream.read<GetAddr>()
                        payload = payload_
                }
                Addr {
			mut payload_ := stream.read<Addr>()
                        payload = payload_
                }
	}
}

pub fn (payload Payload) write(mut stream serialize.Stream) {
	match payload {
		VersionMessage {
			payload.write(mut stream)
		}
		Verack {
			payload.write(mut stream)
		}
		Ping {
			payload.write(mut stream)
		}
		Pong {
			payload.write(mut stream)
		}
                GetAddr {
                        stream.write(payload)
                }
                Addr {
                        stream.write(payload)
                }
	}
}

pub struct Message {
	MessageHeader
pub mut:
	payload Payload
}

pub fn (msg1 Message) == (msg2 Message) bool {
	return msg1.MessageHeader == msg2.MessageHeader && payload_eq(msg1.payload, msg2.payload)
}

pub fn (mut msg Message) read(mut stream serialize.Stream) {
	msg.MessageHeader.read(mut stream)
	match msg.command {
		'aries', 'version' {
			mut payload := VersionMessage{}
			payload.read(mut stream)
			msg.payload = payload
		}
		'verack' {
			mut payload := Verack{}
			payload.read(mut stream)
			msg.payload = payload
		}
		'ping' {
			mut payload := Ping{}
			payload.read(mut stream)
			msg.payload = payload
		}
		'pong' {
			mut payload := Pong{}
			payload.read(mut stream)
			msg.payload = payload
		}
                'getaddr' {
                        msg.payload = stream.read<GetAddr>()
                }
                'addr', 'gridaddr' {
                        msg.payload = stream.read<Addr>()
                }
		else {
			eprintln('Message.read: unknown command ${util.sanitize_binary(msg.command)}')
		}
	}
}

pub fn (msg Message) write(mut stream serialize.Stream) {
	msg.MessageHeader.write(mut stream)
	msg.payload.write(mut stream)
}

pub fn construct_message(payload Payload) Message {
	mut message := Message{}
        message_start2 := message_start
	message.magic = message_start2
	message.payload = payload
	mut checksum_stream := serialize.Stream{}
	checksum_stream.allocate(1024)
	message.write(mut checksum_stream)
	message.length = u32(checksum_stream.offset) - 24
	unsafe {
		checksum := cryptography.double_sha256((checksum_stream.data + 24).vbytes(int(message.length)))
		C.memcpy(&message.checksum, checksum.data, 4)
	}
	message.command = match payload {
		VersionMessage {
			'aries'
		}
		Verack {
			'verack'
		}
		Ping {
			'ping'
		}
		Pong {
			'pong'
		}
                GetAddr {
                        'getaddr'
                }
                Addr {
                        'addr'
                }
	}
	return message
}
