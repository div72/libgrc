module network

import net
import os
import os.notify
import sync
import time

import cryptography
import serialize

const server_port = 22334

const message_start = [u8(0xcd), 0xf2, 0xc0, 0xef]!  // testnet

const protocol_version = 180327

const connect_limit = 15

type PeerPtr = &Peer

pub struct NetworkNode {
pub mut:
        notifier notify.FdNotifier = notify.new() or { panic("failed to create notifier: ${err}") }
	peers shared map[int]PeerPtr
	message_channel chan NetworkMessage = chan NetworkMessage{cap: 16}
        first_node bool = true
        addr_book AddressBook
}

pub fn (mut netnode NetworkNode) get_peer(fd int) &Peer {
    mut peer := &Peer(0)
    lock netnode.peers {
        peer = &Peer(netnode.peers[fd])
    }
    return peer
}

pub fn (netnode &NetworkNode) should_connect(ip string) bool {
    lock netnode.peers {
        if netnode.peers.len > connect_limit {
            return false
        }

        for fd, peer in netnode.peers {
            if ip == &Peer(peer).ip {
                return false
            }
        }
    }

    return true
}

struct NetworkMessage {
mut:
	peer_fd int
	msg Message
}

[heap]
pub struct Peer {
pub mut:
        mutex &sync.Mutex = sync.new_mutex()
	fd int = -1
        ip string = ''
        extrovert bool // fInbound
        connected_at time.Time = time.utc()
        user_agent string
}

pub fn (peer &Peer) get_ip() string {
    return "${net.addr_from_socket_handle(peer.fd)}"
}

pub fn (mut peer Peer) write_msg<T>(obj T) {
    mut stream := serialize.Stream{}
    stream.allocate(4096)
    stream.write(obj)
    stream.seek(0)
    println("writing to $peer.fd - ${typeof(obj).name}")
    peer.mutex.@lock()
    os.fd_write(peer.fd, string{str: stream.data len: stream.len})
    peer.mutex.unlock()
    println("wrote to $peer.fd - ${typeof(obj).name}")
}

pub fn (mut netnode NetworkNode) run() {
	go netnode.process_messages()
	go netnode.connect('127.0.0.1:10001')
        go netnode.cleanup_nodes()
        netnode.listen()

	netnode.message_channel.close()
}

fn (mut netnode NetworkNode) process_messages() {
	mut stream := serialize.Stream{}
	stream.allocate(4096)
	for {
		stream.seek(0)
                stream.len = 0
		peer_msg := <-netnode.message_channel or { return }
                mut peer := netnode.get_peer(peer_msg.peer_fd)
		msg := peer_msg.msg
		println(@FN + ": received ${msg.payload.type_name()} from ${peer_msg.peer_fd}")
		match msg.payload {
			VersionMessage {
                                peer.user_agent = msg.payload.user_agent.clone()
                                if peer.extrovert {
                                    peer.write_msg(construct_message(VersionMessage{}))
                                }
				peer.write_msg(construct_message(Verack{}))
                                if netnode.first_node {
                                    netnode.first_node = false
                                    peer.write_msg(construct_message(GetAddr{}))
                                }
			}
			Ping {
				peer.write_msg(construct_message(Pong{nonce: msg.payload.nonce}))
			}
                        Addr {
                                for addr in msg.payload.list {
                                    if addr.ip[10] == 255 && addr.ip[11] == 255 && addr.port == 60543 {
                                        ip := "${addr.ip[12]}.${addr.ip[13]}.${addr.ip[14]}.${addr.ip[15]}:32748"
                                        if netnode.should_connect(ip) {
                                            netnode.connect(ip)
                                        }
                                    }
                                }
                        }
			else {}
		}
	}
}

fn (mut netnode NetworkNode) connect(ip string) {
        connection := net.dial_tcp(ip) or { return }
        netnode.notifier.add(connection.sock.handle, .read | .peer_hangup) or { eprintln("failed") return}
	lock netnode.peers {
            // FIXME: Workaround for V shared bug.
	    netnode.peers[connection.sock.handle] = &Peer{fd: connection.sock.handle extrovert: false ip: ip}
	}
        mut peer := netnode.get_peer(connection.sock.handle)
        peer.write_msg(construct_message(VersionMessage{}))
}

fn (mut netnode NetworkNode) listen() {
    mut listener := net.listen_tcp(.ip, '127.0.0.1:$server_port') or { panic(err) }
    defer { listener.close() or { eprintln("error while closing listener: ${err}")} }

    netnode.notifier.add(listener.sock.handle, .read) or { panic("error while adding listener for notify: ${err}") }

    for {
        for event in netnode.notifier.wait(time.infinite) {
            match event.fd {
                listener.sock.handle {
                    if connection := listener.accept() {
                        ip := connection.peer_ip() or { eprintln("error while getting ip: ${err}") continue }
                        netnode.notifier.add(connection.sock.handle, .read | .peer_hangup) or { eprintln("error while adding: ${err}") continue }
                        println("New connection from ${ip}.")
                        lock netnode.peers {
                            // TODO: Check existing node?
                            netnode.peers[connection.sock.handle] = &Peer{fd: connection.sock.handle extrovert: true ip: ip}
                        }
                    }
                }
                else {
                    if event.kind.has(.peer_hangup) {
                        eprintln("remote disconnected")
                        netnode.notifier.remove(event.fd) or { panic("error while removing node for notify: ${err}") }
                        continue
                    }

                    mut peer := netnode.get_peer(event.fd)
                    mut s := ""
                    mut len := 0
                    peer.mutex.@lock()
                    s, len = os.fd_read(event.fd, 16384) // TODO: handle larger messages
                    peer.mutex.unlock()
                    if len < 24 {
                        // TODO: add banscore
                        continue
                    }
                    mut stream := serialize.Stream{data: s.str len: len}
                    msg := stream.read<Message>()
                    // TODO: validity checks
                    netnode.message_channel <- NetworkMessage{peer_fd: event.fd msg: msg}
                }
            }
        }
    }
}

pub fn (mut netnode NetworkNode) cleanup_nodes() {
    for {
        now := time.utc()
        shared peers := map[int]PeerPtr{}
        lock peers, netnode.peers {
            for fd, peer_ in netnode.peers {
                mut peer := &Peer(peer_)
                if 30 * time.second > now - peer.connected_at {
                    peers[fd] = peer_
                    continue
                }

                if peer.user_agent == '' {
                    eprintln("disconnect ${fd} not advertising version")
                    os.fd_close(fd)
                    netnode.addr_book.modify_trust(peer.ip, -5)
                    continue
                }

                peers[fd] = peer_
            }
            netnode.peers = peers
        }
        time.sleep(30 * time.second)
    }
}
