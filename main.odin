package main


import "core:encoding/json"
import "core:fmt"
import "core:net"
import rl "vendor:raylib"

// Common types that both server and client need
Network_Message :: struct {
	msg_type:  enum {
		PLAYER_UPDATE,
		GAME_STATE,
		PLAYER_CONNECT,
		PLAYER_DISCONNECT,
	},
	position:  rl.Vector2,
	player_id: int,
}

Multiplayer_State :: struct {
	is_server:       bool,
	socket:          net.Any_Socket,
	clients:         map[int]net.TCP_Socket,
	next_player_id:  int,
	local_player_id: int,
}

Server_Game_State :: struct {
	players:     map[int]Player_State,
	network:     Multiplayer_State,
	should_quit: bool,
}

Player_State :: struct {
	position: rl.Vector2,
	// Add other necessary player state info here
}

PORT :: 27015

main :: proc() {
	run_server()
}
init_server :: proc(server_ip: string = "127.0.0.1") -> (Multiplayer_State, bool) {
	state := Multiplayer_State {
		is_server      = true,
		clients        = make(map[int]net.TCP_Socket),
		next_player_id = 1,
	}

	socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = PORT})
	if err != nil {
		return state, false
	}
	state.socket = socket
	return state, true
}

check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
	peek_buf: [1]byte
	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
	return bytes_read > 0 && err == nil
}

send_message :: proc(socket: net.TCP_Socket, msg: Network_Message) -> bool {
	data, marshal_err := json.marshal(msg)
	if marshal_err != nil {
		return false
	}

	length := len(data)
	length_bytes := transmute([8]byte)length

	bytes_written, send_err := net.send_tcp(socket, length_bytes[:])
	if send_err != nil || bytes_written < 0 {
		return false
	}

	bytes_written, send_err = net.send_tcp(socket, data)
	if send_err != nil || bytes_written < 0 {
		return false
	}

	return true
}

receive_message :: proc(socket: net.TCP_Socket) -> (Network_Message, bool) {
	msg: Network_Message
	length_bytes: [8]byte

	bytes_read, recv_err := net.recv_tcp(socket, length_bytes[:])
	if recv_err != nil || bytes_read < 0 {
		return msg, false
	}

	length := transmute(int)length_bytes
	data := make([]byte, length)
	defer delete(data)

	bytes_read, recv_err = net.recv_tcp(socket, data)
	if recv_err != nil || bytes_read < 0 {
		return msg, false
	}

	unmarshal_err := json.unmarshal(data, &msg)
	if unmarshal_err != nil {
		return msg, false
	}

	return msg, true
}

update_server :: proc(game: ^Server_Game_State) {
	if check_socket_data(game.network.socket.(net.TCP_Socket)) {
		client, source, accept_err := net.accept_tcp(game.network.socket.(net.TCP_Socket))
		if accept_err != nil do return

		player_id := game.network.next_player_id
		game.network.next_player_id += 1
		game.network.clients[player_id] = client

		// Initialize new player state
		game.players[player_id] = Player_State{}

		// Notify other clients
		msg := Network_Message {
			msg_type  = .PLAYER_CONNECT,
			player_id = player_id,
		}

		for _, client_socket in game.network.clients {
			send_message(client_socket, msg)
		}
	}

	// Handle client updates
	for player_id, client_socket in game.network.clients {
		if check_socket_data(client_socket) {
			msg, ok := receive_message(client_socket)
			if !ok {
				delete_key(&game.network.clients, player_id)
				delete_key(&game.players, player_id)
				continue
			}

			if msg.msg_type == .PLAYER_UPDATE {
				if player, ok := &game.players[player_id]; ok {
					player.position = msg.position
				}
			}
		}
	}
}

run_server :: proc() {
	network_state, ok := init_server()
	if !ok {
		fmt.println("Failed to initialize server")
		return
	}

	game := Server_Game_State {
		players     = make(map[int]Player_State),
		network     = network_state,
		should_quit = false,
	}

	fmt.println("Server started on port", PORT)

	for !game.should_quit {
		update_server(&game)
	}

	// Cleanup
	for _, client in game.network.clients {
		net.close(client)
	}
	net.close(game.network.socket)
}
