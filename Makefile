# Thin wrappers around the same commands the workflows run.
# On Podman: unset CONTAINER_HOST and point Docker at the machine socket, e.g.
#   export DOCKER_HOST=unix://$$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')

.PHONY: up down lint probe advisors fix reset

up:
	supabase start

down:
	supabase stop

lint:
	eval "$$(supabase status -o env)"; \
	list() { grep -v '^#' "$$1" | paste -sd, -; }; \
	problems=$$(psql "$$DB_URL" -At -F $$'\t' -v schemas=public \
	  -v public_allow="$$(list rls-public-allowlist.txt)" \
	  -v write_allow="$$(list rls-write-allowlist.txt)" -f rls-lint.sql); \
	echo "$$problems"; \
	if grep -q '^error' <<< "$$problems"; then exit 1; fi

probe:
	eval "$$(supabase status -o env)"; \
	psql "$$DB_URL" -At -F $$'\t' -v schemas=public -f relations.sql > relations.tsv; \
	SUPABASE_URL="$$API_URL" SUPABASE_ANON_KEY="$${PUBLISHABLE_KEY:-$$ANON_KEY}" \
	  PROBE_SIGN_UP=1 node scripts/anon-probe.mts

advisors:
	supabase db advisors --type security --fail-on error

fix:
	./scripts/fix.sh

reset:
	supabase db reset
