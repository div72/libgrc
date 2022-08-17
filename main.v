module main

import time

import chain
import network

struct Node {
mut:
	running bool = true
	network_node &network.NetworkNode = &network.NetworkNode{message_start: chain.testnet_message_start}
}

fn (mut node Node) run() {
	go node.network_node.run()
        for {
            lock node.network_node.peers {
                println("Peer amount: ${node.network_node.peers.len} - Peers:")
                for fd, peer_ in node.network_node.peers {
                    peer := &network.Peer(peer_)
                    println("$fd - ${peer.user_agent} - ${peer.ip}")
                }
            }
            time.sleep(5 * time.second)
        }
}

fn main() {
	mut node := Node{}
	node.run()
}
