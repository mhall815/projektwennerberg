PROJECT=projektwennerberg

# Stack definitions (renamed for clarity)
AUTHENTIK_STACK=authentik
INFRA_STACK=projektwennerberg-infra
AUTHENTIK_COMPOSE=stacks/authentik/docker-compose.yml
INFRA_COMPOSE=stacks/infrastructure/docker-compose.yml

# Secret names
POSTGRES_SECRET=postgres_password
AUTHENTIK_SECRET=authentik_secret_key
CLOUDFLARED_SECRET=cloudflared_token

# Network (renamed for project specificity)
NETWORK=projektwennerberg-net

.PHONY: help
help: ## Show available commands
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Setup ---

.PHONY: bootstrap
bootstrap: network secrets ## Create required network and secrets

.PHONY: network
network: ## Create overlay network if not exists
	@if ! docker network ls | grep -q "$(NETWORK)"; then \
		docker network create --driver overlay $(NETWORK); \
		echo "Created network $(NETWORK)"; \
	else \
		echo "Network $(NETWORK) already exists"; \
	fi

.PHONY: secrets
secrets: ## Create secrets, auto-generating random ones if missing
	@if ! docker secret ls | grep -q $(POSTGRES_SECRET); then \
		openssl rand -base64 32 | tr -d '\n' | docker secret create $(POSTGRES_SECRET) -; \
		echo "Created random secret: $(POSTGRES_SECRET)"; \
	else \
		echo "Secret $(POSTGRES_SECRET) already exists"; \
	fi
	@if ! docker secret ls | grep -q $(AUTHENTIK_SECRET); then \
		openssl rand -base64 60 | tr -d '\n' | docker secret create $(AUTHENTIK_SECRET) -; \
		echo "Created random secret: $(AUTHENTIK_SECRET)"; \
	else \
		echo "Secret $(AUTHENTIK_SECRET) already exists"; \
	fi
	@if ! docker secret ls | grep -q $(CLOUDFLARED_SECRET); then \
		echo "⚠️  Secret $(CLOUDFLARED_SECRET) must be created manually with your Cloudflare token"; \
		echo "Example: echo YOUR_TOKEN | docker secret create $(CLOUDFLARED_SECRET) -"; \
	else \
		echo "Secret $(CLOUDFLARED_SECRET) already exists"; \
	fi

.PHONY: clean-secrets
clean-secrets: ## Remove all project secrets
	@for s in $(POSTGRES_SECRET) $(AUTHENTIK_SECRET); do \
		if docker secret ls | grep -q $$s; then \
			docker secret rm $$s; \
			echo "Removed secret $$s"; \
		fi \
	done

# --- Deployment ---

.PHONY: deploy-authentik
deploy-authentik: ## Deploy Authentik stack
	docker stack deploy -c $(AUTHENTIK_COMPOSE) $(AUTHENTIK_STACK)

.PHONY: deploy-infra
deploy-infra: ## Deploy Infrastructure stack (Traefik, Portainer, etc.)
	docker stack deploy -c $(INFRA_COMPOSE) $(INFRA_STACK)

.PHONY: deploy-all
deploy-all: deploy-infra deploy-authentik ## Deploy all stacks

.PHONY: remove-authentik
remove-authentik: ## Remove Authentik stack
	docker stack rm $(AUTHENTIK_STACK)

.PHONY: remove-infra
remove-infra: ## Remove Infrastructure stack
	docker stack rm $(INFRA_STACK)

.PHONY: remove-all
remove-all: remove-authentik remove-infra ## Remove all stacks

# --- Info ---

.PHONY: ps
ps: ## Show running stacks and services
	docker stack ls
	docker service ls

.PHONY: logs
# Show logs for the infrastructure stack (Traefik, Cloudflared, etc.)
logs-infra:
	docker stack logs -f projektwennerberg-infra

# Show logs for the authentik stack
logs-authentik:
	docker container logs --follow $$(docker container ls --filter "label=com.docker.stack.namespace=authentik" -q)

# Show logs for ALL stacks (can be very noisy)
logs-all:
	docker stack logs -f projektwennerberg-infra & docker stack logs -f authentik

# Kept for convenience: show logs for a single service
logs-traefik:
	docker service logs -f projektwennerberg-infra_traefik

.PHONY: logs-infra logs-authentik logs-all logs-traefik