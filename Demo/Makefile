# PhotonBlog Demo — Build & Run Automation
#
# Usage:
#   make build    - Compile the binary
#   make run      - Build and run the server
#   make test     - Run tests
#   make clean    - Clean build artifacts
#   make docker   - Build Docker image
#   make migrate  - Run database migrations
#   make seed     - Seed database with sample data
#   make serve    - Build and start the server

VFLAGS := -enable-globals
BIN := demo

.PHONY: build run test clean docker migrate seed serve help

build:
	v $(VFLAGS) .

run: build
	./$(BIN) serve

test:
	v $(VFLAGS) test .

clean:
	rm -f $(BIN)
	rm -rf storage/uploads
	rm -f *.db

docker:
	docker build -t photonblog -f Dockerfile ..

migrate: build
	./$(BIN) migrate

seed: build
	./$(BIN) seed

serve: build
	./$(BIN) serve

help:
	@echo "PhotonBlog Demo - Available targets:"
	@echo "  make build    - Compile the binary"
	@echo "  make run      - Build and run the server"
	@echo "  make test     - Run tests"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make docker   - Build Docker image"
	@echo "  make migrate  - Run database migrations"
	@echo "  make seed     - Seed database with sample data"
	@echo "  make serve    - Build and start the server"
