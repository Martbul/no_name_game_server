
ODIN = odin

SERVER_NAME = game_server

# Directories
SERVER_BUILD_DIR = ./build
SERVER_MAIN_FILE = main.odin

# Targets
.PHONY: all server run clean

# Build both client and server
all: server

# Build server
server: $(SERVER_BUILD_DIR)
	$(ODIN) build $(SERVER_MAIN_FILE) -file -out:$(SERVER_BUILD_DIR)/$(SERVER_NAME)

# Run server
run: server
	$(SERVER_BUILD_DIR)/$(SERVER_NAME)

# Create build directory if it doesn't exist
$(SERVER_BUILD_DIR):
	mkdir -p $(SERVER_BUILD_DIR)

# Clean build directories
clean:
	rm -rf $(SERVER_BUILD_DIR)
