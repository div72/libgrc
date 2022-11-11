module network

import log
import net
import os
import os.notify
import sync
import time

import cryptography
import serialize

const protocol_version = 180327

type PeerPtr = &Peer

pub struct NetworkNode {
pub:
        port u16 = 22334
        inbound_connection_limit int = 8
        outbound_connection_limit int = 8
        message_start [4]u8
pub mut:
        notifier notify.FdNotifier = notify.new() or { panic("failed to create notifier: ${err}") }
        send_signal_fd int = -1
	peers shared map[int]PeerPtr
	send_channel chan NetworkMessage = chan NetworkMessage{cap: 16}
	receive_channel chan NetworkMessage = chan NetworkMessage{cap: 16}
        addr_book AddressBook

        logger log.Log = log.Log{level: .info}
}

pub fn (mut netnode NetworkNode) send_msg(fd int, msg Message) {
    netnode.send_channel <- NetworkMessage{peer_fd: fd msg: msg}
    mut buf := [1]u8{}
    C.write(netnode.send_signal_fd, &buf[0], 1)
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
        if netnode.peers.len > netnode.outbound_connection_limit {
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

pub fn (mut netnode NetworkNode) run() {
        for ip in ["45.76.232.146:32748", "3.81.39.58:32748", "104.243.32.211:32748", "67.231.28.123:32748", "185.18.148.223:32748"] {
            netnode.addr_book.add(ip)
            netnode.addr_book.modify_trust(ip, 100)
        }
	go netnode.process_messages()
        go netnode.manage_nodes()
        netnode.listen()

	netnode.send_channel.close()
	netnode.receive_channel.close()
}

pub fn (mut netnode NetworkNode) process_messages() {
	mut stream := serialize.Stream{}
	stream.allocate(16384)
	for {
		stream.seek(0)
                stream.len = 0
		peer_msg := <-netnode.receive_channel or { return }
                mut peer := netnode.get_peer(peer_msg.peer_fd)
		msg := peer_msg.msg
		netnode.logger.debug("received ${msg.payload.type_name()} from ${peer_msg.peer_fd}")
		match msg.payload {
			VersionMessage {
                                peer.user_agent = msg.payload.user_agent.clone()
                                if peer.extrovert {
                                    netnode.send_msg(peer.fd, construct_message(netnode.message_start, VersionMessage{}))
                                }
                                netnode.addr_book.modify_trust(peer.ip, 5)
				netnode.send_msg(peer.fd, construct_message(netnode.message_start, Verack{}))
                                netnode.send_msg(peer.fd, construct_message(netnode.message_start, GetAddr{}))
			}
			Ping {
				netnode.send_msg(peer.fd, construct_message(netnode.message_start, Pong{nonce: msg.payload.nonce}))
			}
                        Addr {
                                for addr in msg.payload.list {
                                    if addr.ip[10] == 255 && addr.ip[11] == 255 {
                                        ip := "${addr.ip[12]}.${addr.ip[13]}.${addr.ip[14]}.${addr.ip[15]}:${C.ntohs(addr.port)}"
                                        netnode.addr_book.add(ip)
                                    }
                                }
                        }
			else {}
		}
	}
}

pub fn (mut netnode NetworkNode) connect(ip string) {
        connection := net.dial_tcp(ip) or { return }
        netnode.notifier.add(connection.sock.handle, .read | .peer_hangup) or {
            netnode.logger.error("failed to add epoll: ${err}") return
        }
	lock netnode.peers {
            // FIXME: Workaround for V shared bug.
	    netnode.peers[connection.sock.handle] = &Peer{fd: connection.sock.handle extrovert: false ip: ip}
	}
        mut peer := netnode.get_peer(connection.sock.handle)
        time.sleep(3)
        netnode.send_msg(peer.fd, construct_message(netnode.message_start, VersionMessage{}))
}

pub fn (mut netnode NetworkNode) listen() {
    mut listener := net.listen_tcp(.ip, '127.0.0.1:${netnode.port}') or { panic(err) }
    defer { listener.close() or { netnode.logger.error("error while closing listener: ${err}")} }

    netnode.notifier.add(listener.sock.handle, .read) or { panic("error while adding listener for notify: ${err}") }

    mut pipe_buf := [256]u8{}
    mut pipefds := [2]int{}
    if C.pipe(&pipefds[0]) != 0 {
        panic("error while creating the pipe")
    }

    netnode.notifier.add(pipefds[0], .read) or { panic("error while adding reader for notify: ${err}") }
    netnode.send_signal_fd = pipefds[1]

    mut stream := serialize.Stream{}
    stream.allocate(4096)

    for {
        for event in netnode.notifier.wait(time.infinite) {
            stream.len = 0
            stream.seek(0)
            match event.fd {
                listener.sock.handle {
                    if connection := listener.accept() {
                        ip := connection.peer_ip() or { netnode.logger.error("error while getting ip: ${err}") continue }
                        netnode.notifier.add(connection.sock.handle, .read | .peer_hangup) or { netnode.logger.error("error while adding: ${err}") continue }
                        netnode.logger.info("New connection from ${ip}.")
                        lock netnode.peers {
                            // TODO: Check existing node?
                            netnode.peers[connection.sock.handle] = &Peer{fd: connection.sock.handle extrovert: true ip: ip}
                        }
                    }
                }
                pipefds[0] {
                    C.read(pipefds[0], &pipe_buf[0], 256)
                    mut msg := NetworkMessage{}
                    for netnode.send_channel.try_pop(mut msg) == .success {
                        // TODO: handle serialization at threads so that network thread has less work to do.
                        stream.len = 0
                        stream.seek(0)
                        stream.write(msg.msg)
                        os.fd_write(msg.peer_fd, tos(stream.data, stream.len))
                    }
                }
                else {
                    if event.kind.has(.peer_hangup) {
                        netnode.logger.debug("remote disconnected")
                        netnode.notifier.remove(event.fd) or { panic("error while removing node for notify: ${err}") }
                        lock netnode.peers {
                            netnode.peers.delete(event.fd)
                        }
                        continue
                    }

                    mut peer := netnode.get_peer(event.fd)
                    mut s := ""
                    mut len := 0
                    time.sleep(400 * time.microsecond)
                    s, len = os.fd_read(event.fd, 16384) // TODO: handle larger messages
                    netnode.logger.debug("Received ${len} bytes from ${event.fd}")
                    if len < 24 {
                        // TODO: add banscore
                        continue
                    }
                    mut stream2 := serialize.Stream{}
                    stream2.data = s.str
                    stream2.len = s.len
                    msg := stream2.read<Message>() or { netnode.logger.debug("failed to parse message") continue }
                    // TODO: validity checks
                    netnode.receive_channel <- NetworkMessage{peer_fd: event.fd msg: msg}
                }
            }
        }
    }
}

pub fn (mut netnode NetworkNode) manage_nodes() {
    for {
        now := time.utc()
        mut to_delete := []int{}
        lock netnode.peers {
            for fd, peer_ in netnode.peers {
                mut peer := &Peer(peer_)
                if (30 * time.second < now - peer.connected_at) && peer.user_agent == '' {
                    netnode.logger.debug("disconnect ${fd} not advertising version")
                    to_delete << fd
                    os.fd_close(fd)
                    netnode.addr_book.modify_trust(peer.ip, -20)
                    continue
                }
            }

            for fd in to_delete {
                netnode.peers.delete(fd)
            }
        }

        netnode.logger.debug("connecting to address book entries")
        lock netnode.addr_book.entries {
            for entry in netnode.addr_book.entries {
                if entry.score < 0 {
                    break
                }

                if netnode.should_connect(entry.ip) {
                    netnode.connect(entry.ip)
                }
            }
        }
        time.sleep(5 * time.second)
    }
}
