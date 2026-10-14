# Run Docker Compose in the development VM while editing this repository on the host.
# Override any setting at invocation time, for example: make VM_PORT=2223 dev-docker
VM_USER ?= $(USER)
VM_HOST ?= 127.0.0.1
VM_PORT ?= 2222
SSH_KEY ?= $(HOME)/.ssh/id_rsa
REMOTE_DIR ?= /home/$(VM_USER)/src/$(notdir $(CURDIR))
COMPOSE_ARGS ?= --build
COMPOSE_COMMAND ?= ps
DOCKER_COMMAND ?= ps

SSH = ssh -i "$(SSH_KEY)" -o IdentitiesOnly=yes -p "$(VM_PORT)" "$(VM_USER)@$(VM_HOST)"
RSYNC_RSH = ssh -i "$(SSH_KEY)" -o IdentitiesOnly=yes -p "$(VM_PORT)"

.PHONY: sync compose docker dev-docker dev-docker-detached docker-down

# Mirror the working tree into the VM. --delete keeps the guest copy faithful
# to the host; .git stays on the host, so Git is never needed in the VM.
sync:
	$(SSH) 'mkdir -p "$(REMOTE_DIR)"'
	rsync -az --delete \
		--exclude '.git/' \
		--exclude 'vm/' \
		--exclude '.DS_Store' \
		-e '$(RSYNC_RSH)' \
		./ "$(VM_USER)@$(VM_HOST):$(REMOTE_DIR)/"

# Run any Docker Compose command in the VM. For example:
# make compose COMPOSE_COMMAND='down --volumes'
compose: sync
	$(SSH) 'cd "$(REMOTE_DIR)" && docker compose $(COMPOSE_COMMAND)'

# Run a Docker command in the VM that is not tied to this Compose project.
# For example: make docker DOCKER_COMMAND='image ls'
docker:
	$(SSH) 'docker $(DOCKER_COMMAND)'

# Start the complete Compose stack in the foreground. Ctrl-C stops the Compose
# command in the VM; use `make docker-down` to remove the stack explicitly.
dev-docker: sync
	$(SSH) 'cd "$(REMOTE_DIR)" && docker compose up $(COMPOSE_ARGS)'

# Useful when the development stack should remain running after Make exits.
dev-docker-detached: sync
	$(SSH) 'cd "$(REMOTE_DIR)" && docker compose up $(COMPOSE_ARGS) -d'

docker-down:
	$(SSH) 'cd "$(REMOTE_DIR)" && docker compose down'
