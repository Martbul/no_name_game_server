package main

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:thread"
import rl "vendor:raylib"

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
}

PORT :: 27015

main :: proc() {
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


init_server :: proc(server_ip: string = "127.0.0.1") -> (Multiplayer_State, bool) {
	state := Multiplayer_State {
		is_server      = true,
		clients        = make(map[int]net.TCP_Socket),
		next_player_id = 1,
	}

	address, ok := net.parse_ip4_address(server_ip)
	if !ok {
		fmt.println("Failed to parse IP address")
		return state, false
	}

	socket, err := net.listen_tcp(net.Endpoint{address = address, port = PORT})
	if err != nil {
		fmt.println("Failed to create listening socket:", err)
		return state, false
	}

	fmt.println("Server listening socket created successfully")
	state.socket = socket
	return state, true
}
update_server :: proc(game: ^Server_Game_State) {
	// Accept new connections
	server_socket := game.network.socket.(net.TCP_Socket)

	client, source, accept_err := net.accept_tcp(server_socket)
	if accept_err == nil {
		fmt.printf("New client connected from: %v\n", source)
		player_id := game.network.next_player_id
		game.network.next_player_id += 1
		game.network.clients[player_id] = client
		game.players[player_id] = Player_State{}

		// Notify new client about their ID
		connect_msg := Network_Message {
			msg_type  = .PLAYER_CONNECT,
			player_id = player_id,
		}
		send_message(client, connect_msg)
		fmt.println("New client connected, assigned ID:", player_id)
	}

	// Handle updates from connected clients
	to_disconnect := make([dynamic]int)
	defer delete(to_disconnect)

	for player_id, client_socket in game.network.clients {
		// Non-blocking check for data
		peek_buf: [1]byte
		bytes_read, peek_err := net.recv_tcp(client_socket, peek_buf[:])
		if peek_err != nil {
			fmt.printf("Error checking client %v: %v\n", player_id, peek_err)
			append(&to_disconnect, player_id)
			continue
		}
		if bytes_read <= 0 {
			continue // No data available
		}

		msg, ok := receive_message(client_socket)
		if !ok {
			fmt.printf("Failed to receive message from client %v\n", player_id)
			continue
		}

		fmt.printf("Received message type %v from player %v\n", msg.msg_type, player_id)

		#partial switch msg.msg_type {
		case .PLAYER_UPDATE:
			player_state := game.players[player_id]
			player_state.position = msg.position
			game.players[player_id] = player_state
			fmt.printf(
				"Updated player %v position to [%f, %f]\n",
				player_id,
				msg.position.x,
				msg.position.y,
			)

			// Broadcast to other clients
			for other_id, other_socket in game.network.clients {
				if other_id != player_id {
					if !send_message(other_socket, msg) {
						fmt.printf("Failed to send update to client %v\n", other_id)
					}
				}
			}
		}
	}

	// Handle disconnections
	for disconnect_id in to_disconnect {
		fmt.println("Disconnecting client:", disconnect_id)
		if client_socket, ok := game.network.clients[disconnect_id]; ok {
			net.close(client_socket)
		}
		delete_key(&game.network.clients, disconnect_id)
		delete_key(&game.players, disconnect_id)
	}
}

encode_length :: proc(length: u64) -> [8]byte {
	return [8]byte {
		byte(length >> 56),
		byte(length >> 48),
		byte(length >> 40),
		byte(length >> 32),
		byte(length >> 24),
		byte(length >> 16),
		byte(length >> 8),
		byte(length),
	}
}

decode_length :: proc(bytes: [8]byte) -> u64 {
	return(
		u64(bytes[0]) << 56 |
		u64(bytes[1]) << 48 |
		u64(bytes[2]) << 40 |
		u64(bytes[3]) << 32 |
		u64(bytes[4]) << 24 |
		u64(bytes[5]) << 16 |
		u64(bytes[6]) << 8 |
		u64(bytes[7]) \
	)
}
//update_server :: proc(game: ^Server_Game_State) {
// Accept new connections
//	server_socket := game.network.socket.(net.TCP_Socket)

// Change this part - don't use check_socket_data for the listening socket
//	client, source, accept_err := net.accept_tcp(server_socket)
//	if accept_err == nil {
//		fmt.printf("New client connected from: %v\n", source)
//		player_id := game.network.next_player_id
//		game.network.next_player_id += 1
//		game.network.clients[player_id] = client
//		game.players[player_id] = Player_State{}
///
//		// Notify new client about their ID
//		connect_msg := Network_Message {
//			msg_type  = .PLAYER_CONNECT,
//			player_id = player_id,
//		}
//		send_message(client, connect_msg)
//
//		// Notify existing clients about new player
///		for existing_id, client_socket in game.network.clients {
///			if existing_id != player_id {
//				send_message(client_socket, connect_msg)
///			}
//		}
//
//		fmt.println("New client connected, assigned ID:", player_id)
//	}
//
//	//fmt.printf("Number of connected clients: %v\n", len(game.network.clients))
///	// Handle updates from connected clients
//	for player_id, client_socket in game.network.clients {
//		fmt.printf("Checking client %v (socket: %v)\n", player_id, client_socket)
//		if !check_socket_data(client_socket) {
//			fmt.println("No data from client", player_id)
//			continue
//		}
//		fmt.println("Receiving message from client", player_id)
//		msg, ok := receive_message(client_socket)
///		if !ok {
//			fmt.println("Client disconnected:", player_id)
//			// Notify other clients about disconnection
//			disconnect_msg := Network_Message {
//				msg_type  = .PLAYER_DISCONNECT,
//				player_id = player_id,
//			}
//			for other_id, other_socket in game.network.clients {
///				if other_id != player_id {
//					send_message(other_socket, disconnect_msg)
//				}
//			}
//			delete_key(&game.network.clients, player_id)
//			delete_key(&game.players, player_id)
//			net.close(client_socket)
//			continue
//		}
///
//		// Broadcast position updates to other clients
//		if msg.msg_type == .PLAYER_UPDATE {
//			// Create new player state with updated position
//			player_state := game.players[player_id]
//			player_state.position = msg.position
///			game.players[player_id] = player_state
//
//			for other_id, other_socket in game.network.clients {
//				if other_id != player_id {
//					send_message(other_socket, msg)
//				}
//			}
//		}
//	}
//}

check_socket_data :: proc(socket: net.TCP_Socket) -> bool {
	peek_buf: [1]byte
	bytes_read, err := net.recv_tcp(socket, peek_buf[:])
	if err != nil {
		fmt.printf("Socket check error: %v\n", err)
		return false
	}
	return bytes_read > 0
}
send_message :: proc(socket: net.TCP_Socket, msg: Network_Message) -> bool {
	data, marshal_err := json.marshal(msg)
	if marshal_err != nil {
		fmt.println("Marshal error:", marshal_err)
		return false
	}

	length := u64(len(data))
	if length == 0 || length > 1024 * 1024 {
		fmt.println("Invalid message length:", length)
		return false
	}

	fmt.printf("Sending message: %s\n", string(data))
	length_bytes := encode_length(length)
	fmt.printf("Length encoded: %v (decimal: %v)\n", length_bytes, length)

	// Send length prefix and data
	send_all := proc(data: []byte, socket: net.TCP_Socket) -> bool {
		total_sent := 0
		for total_sent < len(data) {
			bytes_sent, send_err := net.send_tcp(socket, data[total_sent:])
			if send_err != nil {
				fmt.printf("Send error: %v\n", send_err)
				return false
			}
			if bytes_sent <= 0 {
				fmt.println("Socket closed during send")
				return false
			}
			total_sent += bytes_sent
		}
		return true
	}

	if !send_all(length_bytes[:], socket) {
		fmt.println("Failed to send length prefix")
		return false
	}
	if !send_all(data, socket) {
		fmt.println("Failed to send message data")
		return false
	}
	return true
}

//receive_message :: proc(socket: net.TCP_Socket) -> (Network_Message, bool) {
//	msg: Network_Message
//	length_bytes: [8]byte
//
//	fmt.println("Attempting to read message length...")
//	// Read length prefix with timeout
//	total_read := 0
//	for total_read < 8 {
//		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
//		if recv_err != nil {

//			fmt.println("Error reading length:", recv_err)
//			return msg, false
//		}
//		if bytes_read <= 0 {
//
//			fmt.println("Socket closed or no data received.")
//			return msg, false
//		}
//
//		fmt.println("Bytes read for length prefix:", total_read)
//		total_read += bytes_read
//	}

//	length :=
//		u64(length_bytes[0]) << 56 |
//		u64(length_bytes[1]) << 48 |
//		u64(length_bytes[2]) << 40 |
//		u64(length_bytes[3]) << 32 |
//		u64(length_bytes[4]) << 24 |
///		u64(length_bytes[5]) << 16 |
//		u64(length_bytes[6]) << 8 |
//		u64(length_bytes[7])

//	fmt.println("Message length received:", length)
//	if length == 0 || length > 1024 * 1024 {
//		fmt.println("Invalid message length:", length)
//		return msg, false
//	}

//	data := make([]byte, length)
//	defer delete(data)

//	fmt.println("Attempting to read full message data...")
//	total_read = 0
//	for total_read < int(length) {
//		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
//		if recv_err != nil {
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			return msg, false
//		}

//		total_read += bytes_read
//	}

//	fmt.println("Attempting to deserialize message...")
//	unmarshal_err := json.unmarshal(data, &msg)
//	if unmarshal_err != nil {
//		fmt.println("Unmarshal error:", unmarshal_err)
//		return msg, false
//	}

//	fmt.println("Message received successfully!")
///	return msg, true
//}
receive_message :: proc(socket: net.TCP_Socket) -> (Network_Message, bool) {
	msg: Network_Message
	length_bytes: [8]byte

	// Read length prefix
	total_read := 0
	for total_read < 8 {
		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
		if recv_err != nil {
			fmt.printf("Error reading length prefix: %v\n", recv_err)
			return msg, false
		}
		if bytes_read <= 0 {
			return msg, false
		}
		total_read += bytes_read
	}

	length := decode_length(length_bytes)
	fmt.printf("Length decoded: %v from bytes: %v\n", length, length_bytes)

	if length == 0 || length > 1024 * 1024 {
		fmt.printf("Invalid message length: %v\n", length)
		return msg, false
	}

	data := make([]byte, length)
	defer delete(data)

	// Read message data
	total_read = 0
	for total_read < int(length) {
		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
		if recv_err != nil {
			fmt.printf("Error reading message data: %v\n", recv_err)
			return msg, false
		}
		if bytes_read <= 0 {
			return msg, false
		}
		total_read += bytes_read
	}

	fmt.printf("Received complete message: %s\n", string(data))

	unmarshal_err := json.unmarshal(data, &msg)
	if unmarshal_err != nil {
		fmt.printf("Unmarshal error: %v\n", unmarshal_err)
		return msg, false
	}

	return msg, true
}

//receive_message :: proc(socket: net.TCP_Socket) -> (Network_Message, bool) {
//	msg: Network_Message
//	length_bytes: [8]byte

// Read 8-byte length prefix
///	fmt.println("Attempting to read message length...")
//	total_read := 0
//	for total_read < 8 {
//		bytes_read, recv_err := net.recv_tcp(socket, length_bytes[total_read:])
//		if recv_err != nil {
//			fmt.println("Error reading length:", recv_err)
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			fmt.println("Socket closed or no data received.")
//			return msg, false
//		}
//		total_read += bytes_read
//		fmt.println("Bytes read for length prefix:", total_read)
//	}
//
//	// Decode the length
//	length :=
//		u64(length_bytes[0]) << 56 |
//		u64(length_bytes[1]) << 48 |
//		u64(length_bytes[2]) << 40 |
//		u64(length_bytes[3]) << 32 |
//		u64(length_bytes[4]) << 24 |
//		u64(length_bytes[5]) << 16 |
//		u64(length_bytes[6]) << 8 |
//		u64(length_bytes[7])
//	fmt.println("Message length received:", length)
//
//	if length == 0 || length > 1024 * 1024 {
//		fmt.println("Invalid message length:", length)
//		return msg, false
//	}
//
//	data := make([]byte, length)
//	defer delete(data)
//
//	// Read full message data
//	fmt.println("Attempting to read full message data...")
//	total_read = 0
//	for total_read < int(length) {
//		bytes_read, recv_err := net.recv_tcp(socket, data[total_read:])
//		if recv_err != nil {
//			fmt.println("Error reading data:", recv_err)
//			return msg, false
//		}
//		if bytes_read <= 0 {
//			fmt.println("Socket closed or no data received while reading message.")
//			return msg, false
//		}
//		total_read += bytes_read
//		fmt.println("Bytes read for message data:", total_read, "/", length)
//	}

// Deserialize JSON message
//	fmt.println("Attempting to deserialize message...")
//	unmarshal_err := json.unmarshal(data, &msg)
//	if unmarshal_err != nil {
//		fmt.println("Unmarshal error:", unmarshal_err)
//		return msg, false
//	}
//
//	fmt.println("Message received successfully!")
//	return msg, true
//}
