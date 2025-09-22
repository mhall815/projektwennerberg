SHELL = /bin/bash

# --- Contents of: ./Makefile ---
PROJECT=projektwennerberg

# Stack definitions
INFRA_STACK=projektwennerberg-infra
AUTHENTIK_STACK=authentik
HELLO_STACK=helloworld
INFRA_COMPOSE=stacks/infrastructure/docker-compose.yml
AUTHENTIK_COMPOSE=stacks/authentik/docker-compose.yml
HELLO_COMPOSE=stacks/hello-world/docker-compose.yml
AUTHENTIK_OUTPOST_TOKEN_SECRET=authentik_outpost_token # <--- ADD THIS LINE

# Secret names - Infrastructure
POSTGRES_SECRET=postgres_password
AUTHENTIK_SECRET=authentik_secret_key
CLOUDFLARED_SECRET=cloudflared_token

# Secret names - User passwords
ADMIN_PASSWORD_SECRET=authentik_admin_password
DEMO_PASSWORD_SECRET=authentik_demo_password

# Network
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
	# Infrastructure secrets
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

.PHONY: add-outpost-token
add-outpost-token: ## Create the authentik outpost token secret interactively
	@if docker secret ls | grep -q "$(AUTHENTIK_OUTPOST_TOKEN_SECRET)"; then \
		echo "⚠️  Secret $(AUTHENTIK_OUTPOST_TOKEN_SECRET) already exists."; \
		echo "   To replace it, first run: docker secret rm $(AUTHENTIK_OUTPOST_TOKEN_SECRET)"; \
	else \
		read -sp "Paste Authentik Outpost Token: " token; \
		if [ -z "$$token" ]; then \
			echo "\n❌ No token provided. Aborting."; \
		else \
			printf "%s" "$$token" | docker secret create $(AUTHENTIK_OUTPOST_TOKEN_SECRET) - > /dev/null; \
			echo "\n✅ Secret $(AUTHENTIK_OUTPOST_TOKEN_SECRET) created successfully."; \
		fi; \
	fi


.PHONY: clean-secrets
clean-secrets: ## Remove all project secrets (preserves Cloudflare token)
	@for s in $(POSTGRES_SECRET) $(AUTHENTIK_SECRET) $(ADMIN_PASSWORD_SECRET) $(DEMO_PASSWORD_SECRET); do \
		if docker secret ls | grep -q "$$s"; then \
			docker secret rm "$$s"; \
			echo "Removed secret $$s"; \
		fi; \
	done

.PHONY: clean-volumes
clean-volumes: ## Remove all project volumes (WARNING: destroys data!)
	@echo "🚨 This will remove ALL project volumes and destroy data!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "Removing project volumes..."
	@for v in $$(docker volume ls -q | grep -E "(authentik|traefik|projektwennerberg)" || true); do \
		if [ -n "$$v" ]; then \
			echo "Removing volume: $$v"; \
			docker volume rm "$$v" 2>/dev/null || echo "Volume $$v already removed or in use"; \
		fi; \
	done

.PHONY: nuclear-reset
nuclear-reset: ## 💥 NUCLEAR RESET: Remove everything except Cloudflare secret, recreate from scratch
	@echo "💥 NUCLEAR RESET: This will destroy ALL data and recreate everything!"
	@echo "⚠️  Data that will be LOST:"
	@echo "   - All Authentik users, groups, and configuration"
	@echo "   - All PostgreSQL data"
	@echo "   - All Redis cache data"
	@echo "   - All application state"
	@echo ""
	@echo "🔒 Data that will be PRESERVED:"
	@echo "   - Cloudflare tunnel token"
	@echo "   - Docker network configuration"
	@echo ""
	@read -p "Type NUCLEAR and press enter: " confirm && [ "$$confirm" = "NUCLEAR" ] || { echo "Cancelled"; exit 1; }
	@echo ""
	@echo "🚀 Starting nuclear reset..."
	@echo ""
	# Step 1: Remove all stacks
	@echo "📦 Removing all stacks..."
	@$(MAKE) remove-all || true
	@sleep 5
	# Step 2: Clean secrets (except Cloudflare)
	@echo "🔑 Cleaning secrets..."
	@$(MAKE) clean-secrets
	@sleep 5
	# Step 3: Clean volumes
	@echo "💾 Cleaning volumes..."
	@for v in $$(docker volume ls -q | grep -E "(authentik|traefik|projektwennerberg)" || true); do \
		if [ -n "$$v" ]; then \
			echo "Removing volume: $$v"; \
			docker volume rm "$$v" 2>/dev/null || echo "Volume $$v already removed or in use"; \
		fi; \
	done
	@sleep 2
	# Step 4: Recreate secrets and network
	@echo "🔧 Recreating infrastructure..."
	@$(MAKE) bootstrap
	@sleep 3
	# Step 5: Deploy everything
	@echo "🚀 Deploying all services..."
	@$(MAKE) deploy-all
	@sleep 5
	# Step 6: Show status
	@echo ""
	@echo "✅ Nuclear reset complete!"
	@echo ""
	@echo ""
	@echo "📊 Service status:"
	@$(MAKE) ps
	@echo ""
	@echo "🌐 Access URLs:"
	@echo "   - Authentik:     https://auth.projektwennerberg.org"
	@echo "   - Traefik:       https://traefik.projektwennerberg.org"
	@echo "   - Hello World:   https://projektwennerberg.org"
	@echo ""
	@echo "⏰ Services may take a few minutes to become fully available."

.PHONY: soft-reset
soft-reset: ## 🔄 Soft reset: Restart services without destroying data
	@echo "🔄 Performing soft reset (restarting services)..."
	@$(MAKE) remove-all
	@sleep 5
	@$(MAKE) deploy-all
	@echo "✅ Soft reset complete!"
	@$(MAKE) ps


# --- Deployment ---

.PHONY: deploy-infra
deploy-infra: ## Deploy Infrastructure stack (Traefik, etc.)
	docker stack deploy -c $(INFRA_COMPOSE) $(INFRA_STACK)

.PHONY: deploy-authentik
deploy-authentik: ## Deploy Authentik stack
	docker stack deploy -c $(AUTHENTIK_COMPOSE) $(AUTHENTIK_STACK)

.PHONY: deploy-hello
deploy-hello: ## Deploy Hello World stack
	docker stack deploy -c $(HELLO_COMPOSE) $(HELLO_STACK)

.PHONY: deploy-all
deploy-all: deploy-infra deploy-authentik deploy-hello ## Deploy all stacks

.PHONY: remove-infra
remove-infra: ## Remove Infrastructure stack
	docker stack rm $(INFRA_STACK)

.PHONY: remove-authentik
remove-authentik: ## Remove Authentik stack
	docker stack rm $(AUTHENTIK_STACK)

.PHONY: remove-hello
remove-hello: ## Remove Hello World stack
	docker stack rm $(HELLO_STACK)

.PHONY: remove-all
remove-all: remove-infra remove-authentik remove-hello ## Remove all stacks

# --- Info ---

.PHONY: ps
ps: ## Show running stacks and services
	docker stack ls
	docker service ls

.PHONY: logs-infra
logs-infra: ## Show logs for the infrastructure stack
	docker service logs -f $(INFRA_STACK)_traefik

.PHONY: logs-authentik
logs-authentik: ## Show logs for the Authentik stack
	docker service logs -f $(AUTHENTIK_STACK)_server

.PHONY: logs-hello
logs-hello: ## Show logs for the Hello World stack
	docker service logs -f $(HELLO_STACK)_hello

.PHONY: logs-traefik
logs-traefik: ## Show logs for Traefik service
	docker service logs -f $(INFRA_STACK)_traefik