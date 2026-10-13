IMAGE     := networkd-wait-online
SCENARIO  ?= stuck
NAME      := $(IMAGE)-$(SCENARIO)
SCENARIOS := $(notdir $(wildcard scenarios/*))

# systemd as PID 1 needs a privileged container with its own cgroup namespace.
# --network none leaves only lo, so eth0/eth1 are the ones fake-cables makes.
RUN_FLAGS := --privileged --cgroupns=private --network none \
             --tmpfs /run --tmpfs /run/lock \
             -e SCENARIO=$(SCENARIO)

.PHONY: build list up wait demo demo-all report shell plug unplug down clean

build:
	docker build -q -t $(IMAGE) . >/dev/null

list:
	@echo $(SCENARIOS)

# Boots the scenario in the background and leaves it running.
up: build
	@docker rm -f $(NAME) >/dev/null 2>&1 || true
	@docker run -d --name $(NAME) $(RUN_FLAGS) $(IMAGE) >/dev/null
	@echo "started $(NAME)"

# Polls until boot has finished: "running", or "degraded" when wait-online
# failed, which is an expected outcome here.
wait:
	@docker exec $(NAME) sh -c 'for i in $$(seq 300); do \
		case "$$(systemctl is-system-running 2>/dev/null)" in running|degraded) exit 0;; esac; \
		sleep 0.5; done; echo "boot did not finish" >&2; exit 1'

# Boots the scenario, waits for boot to finish, prints the report, removes it.
demo: up wait report
	@docker rm -f $(NAME) >/dev/null

demo-all: build
	@for s in $(SCENARIOS); do $(MAKE) --no-print-directory demo SCENARIO=$$s; echo; done

report:
	@docker exec -e SCENARIO=$(SCENARIO) $(NAME) report

shell:
	docker exec -it $(NAME) bash

# Plug / unplug eth1's cable (with a DHCP server behind it) on a running scenario.
plug:
	docker exec $(NAME) plug-eth1

unplug:
	docker exec $(NAME) unplug-eth1

down:
	@docker rm -f $(NAME) >/dev/null 2>&1 || true

clean:
	@docker rm -f $(addprefix $(IMAGE)-,$(SCENARIOS)) >/dev/null 2>&1 || true
	@docker rmi -f $(IMAGE) >/dev/null 2>&1 || true
