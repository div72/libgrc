module network

import serialize

fn test_serialize_message_header() {
	mut stream := serialize.Stream{}
	h := MessageHeader{magic: [u8(0xcd), 0xf2, 0xc0, 0xef]! command: 'nop' length: 0}
	h.write(mut stream)
	old_offset := stream.seek(0)
	mut h2 := MessageHeader{}
	h2.read(mut stream)
	assert h2 == h
	assert old_offset == stream.offset
}

fn test_serialize_aries() {
	target := [u8(`e`), 0xc0, 0x02, `\0`, 0x01, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, 0x15, 0x1e, 0x17, 0x60, `\0`, `\0`, `\0`, `\0`, `\0`, 0xe1, 0xf5, 0x05, 0x01, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, 0xff, 0xff, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, 0x15, 0x1e, 0x17, 0x60, 0x01, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, `\0`, 0xff, 0xff, `d`, `t`, 0x15, 0xa1, 0x7f, 0xec, 0xff, 0x9e, 0xd3, 0xeb, 0x8e, 0xd9, 0xa0, 0x91, 0x11, `/`, `H`, `a`, `l`, `f`, `o`, `r`, `d`, `:`, `5`, `.`, `1`, `.`, `0`, `.`, `9`, `/`, 0x89, 0x95, 0x16, `\0`]
    mut stream := serialize.Stream{}
    stream.allocate(110)
    payload := VersionMessage{
        version: 180325
        services: 1
        timestamp: 1612127765
        addr_recv: network.Address{
            time: 100000000
            services: 1
            ip: [u8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 0, 0, 0, 0]!
            port: 0
        }
        addr_from: network.Address{
            time: 1612127765
            services: 1
            ip: [u8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 100, 116, 21, 161]!
            port: 60543
        }
        nonce: 10493626339638353663
        user_agent: '/Halford:5.1.0.9/'
        start_height: 1480073
    }
    payload.write(mut stream)
    assert stream.data.vbytes(110) == target
}

fn test_reserialize_aries() {
	mut stream := serialize.Stream{}
	msg := construct_message(VersionMessage{})
	msg.write(mut stream)
	old_offset := stream.seek(0)
	mut msg2 := Message{}
	msg2.read(mut stream)
	assert msg2 == msg
	assert old_offset == stream.offset
}

fn test_construct_aries() {
	msg1 := network.Message{
    MessageHeader: network.MessageHeader{
        magic: [u8(205), 242, 192, 239]!
        command: 'aries'
        length: 110
        checksum: [u8(6), 184, 29, 202]!
    }
    payload: network.Payload(network.VersionMessage{
        version: 180325
        services: 1
        timestamp: 1612128020
        addr_recv: network.Address{
            time: 100000000
            services: 1
            ip: [u8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 0, 0, 0, 0]!
            port: 0
        }
        addr_from: network.Address{
            time: 1612128020
            services: 1
            ip: [u8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 100, 116, 21, 161]!
            port: 60543
        }
        nonce: 4486298760406690637
        user_agent: '/Halford:5.1.0.9/'
        start_height: 1480077
    })
    }
	msg2 := construct_message(msg1.payload)
	assert msg1 == msg2
}
