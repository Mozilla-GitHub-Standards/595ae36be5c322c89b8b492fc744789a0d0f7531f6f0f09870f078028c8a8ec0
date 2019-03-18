# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# Copyright (c) 2014 Mozilla Corporation
#

ROOT_DIR	:= $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DKR_IMAGES	:= mozdef_alertplugins mozdef_alerts mozdef_base mozdef_bootstrap mozdef_meteor mozdef_rest \
		   mozdef_mq_worker mozdef_loginput mozdef_cron mozdef_elasticsearch mozdef_mongodb \
		   mozdef_syslog mozdef_nginx mozdef_tester mozdef_rabbitmq mozdef_kibana
BUILD_MODE	:= build  ## Pass `pull` in order to pull images instead of building them
NAME		:= mozdef
VERSION		:= 0.1
BRANCH		:= master
NO_CACHE	:= ## Pass `--no-cache` in order to disable Docker cache
GITHASH		:= latest  ## Pass `$(git rev-parse --short HEAD`) to tag docker hub images as latest git-hash instead
TEST_CASE	:= tests  ## Run all (`tests`) or a specific test case (ex `tests/alerts/tests/alerts/test_proxy_drop_exfil_domains.py`)
TMPDIR      := $(shell mktemp -d )

.PHONY:all
all:
	@echo 'Available make targets:'
	@grep '^[^#[:space:]^\.PHONY.*].*:' Makefile

.PHONY: run
run: build ## Run all MozDef containers
	docker-compose -f docker/compose/docker-compose.yml -p $(NAME) up -d

.PHONY: run-cloudy-mozdef restart-cloudy-mozdef
run-cloudy-mozdef: ## Run the MozDef containers necessary to run in AWS (`cloudy-mozdef`). This is used by the CloudFormation-initiated setup.
	$(shell test -f docker/compose/cloudy_mozdef.env || touch docker/compose/cloudy_mozdef.env)
	$(shell test -f docker/compose/cloudy_mozdef_kibana.env || touch docker/compose/cloudy_mozdef_kibana.env)
	docker-compose -f docker/compose/docker-compose-cloudy-mozdef.yml -p $(NAME) pull
	docker-compose -f docker/compose/docker-compose-cloudy-mozdef.yml -p $(NAME) up -d

.PHONY: run-env-mozdef
run-env-mozdef: ## Run the MozDef containers with a user specified env file. Run with make 'run-env-mozdef -e ENV=my.env'
ifneq ("$(wildcard $(ENV))","") #Check for existence of ENV
	ENV_FILE=$(abspath $(ENV)) docker-compose -f docker/compose/docker-compose.yml -f docker/compose/docker-compose-user-env.yml -p $(NAME) up -d
else
	@echo $(ENV) not found.
endif

restart-cloudy-mozdef:
	docker-compose -f docker/compose/docker-compose-cloudy-mozdef.yml -p $(NAME) restart

.PHONY: tests run-tests-resources run-tests-resources-external run-tests
test: build-tests run-tests
tests: build-tests run-tests  ## Run all tests (getting/building images as needed)
run-tests-resources-external: ## Just spin up external resources for tests and have them listen externally
	docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) run -p 9200:9200 -d elasticsearch
	docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) run -p 5672:5672 -d rabbitmq
run-tests-resources:  ## Just run the external resources required for tests
	docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) up -d
run-test:
run-tests: run-tests-resources  ## Just run the tests (no build/get). Use `make TEST_CASE=tests/...` for specific tests only
	docker run -it --rm mozdef/mozdef_tester bash -c "source /opt/mozdef/envs/python/bin/activate && flake8 --config .flake8 ./"
	docker run -it --rm --network=test-mozdef_default mozdef/mozdef_tester bash -c "source /opt/mozdef/envs/python/bin/activate && py.test --delete_indexes --delete_queues $(TEST_CASE)"
rebuild-run-tests: build-tests run-tests


.PHONY: build-cwd
build-from-cwd:  ## Build local MozDef images (use make NO_CACHE=--no-cache build to disable caching)
	docker-compose -f docker/compose/docker-compose.yml -p $(NAME) $(NO_CACHE) $(BUILD_MODE)

.PHONY: build-github
build-from-github:  ## Build local MozDef images from the github branch (use make NO_CACHE=--no-cache build to disable caching)
	@echo "Performing a build from the github branch using $(TMPDIR) for BRANCH=$(BRANCH)"
	cd $(TMPDIR) && git clone https://github.com/mozilla/MozDef.git && cd MozDef && git checkout $(BRANCH) && make build-from-cwd
	rm -rf $(TMPDIR)

.PHONY: build-tests
build-tests:  ## Build end-to-end test environment only
	docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) $(NO_CACHE) $(BUILD_MODE)

.PHONY: stop down
stop: down
down: ## Shutdown all services we started with docker-compose
	docker-compose -f docker/compose/docker-compose.yml -p $(NAME) stop
	docker-compose -f docker/compose/docker-compose.yml -p test-$(NAME) stop

.PHONY: docker-push docker-get hub hub-get
docker-push: hub
hub: ## Upload locally built MozDef images tagged as the current git head (hub.docker.com/mozdef).
	docker login
	docker-compose -f docker/compose/docker-compose.yml -p $(NAME) push
	docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) push

.PHONY: docker-push-tagged docker-get hub hub-get
docker-push-tagged: hub-tagged
hub-tagged: ## Upload locally built MozDef images tagged as the current git head (hub.docker.com/mozdef).
	docker login
	docker tag mozdef/mozdef_meteor:latest mozdef/mozdef_meteor:$(BRANCH) && docker push mozdef/mozdef_meteor:$(BRANCH)
	docker tag mozdef/mozdef_base:latest mozdef/mozdef_base:$(BRANCH) && docker push mozdef/mozdef_base:$(BRANCH)
	docker tag mozdef/mozdef_tester:latest mozdef/mozdef_tester:$(BRANCH) && docker push mozdef/mozdef_tester:$(BRANCH)
	docker tag mozdef/mozdef_mq_worker:latest mozdef/mozdef_mq_worker:$(BRANCH) && docker push mozdef/mozdef_mq_worker:$(BRANCH)
	docker tag mozdef/mozdef_kibana:latest mozdef/mozdef_kibana:$(BRANCH) && docker push mozdef/mozdef_kibana:$(BRANCH)
	docker tag mozdef/mozdef_syslog:latest mozdef/mozdef_syslog:$(BRANCH) && docker push mozdef/mozdef_syslog:$(BRANCH)
	docker tag mozdef/mozdef_cron:latest mozdef/mozdef_cron:$(BRANCH) && docker push mozdef/mozdef_cron:$(BRANCH)
	docker tag mozdef/mozdef_elasticsearch:latest mozdef/mozdef_elasticsearch:$(BRANCH) && docker push mozdef/mozdef_elasticsearch:$(BRANCH)
	docker tag mozdef/mozdef_loginput:latest mozdef/mozdef_loginput:$(BRANCH) && docker push mozdef/mozdef_loginput:$(BRANCH)
	docker tag mozdef/mozdef_mongodb:latest mozdef/mozdef_mongodb:$(BRANCH) && docker push mozdef/mozdef_mongodb:$(BRANCH)
	docker tag mozdef/mozdef_bootstrap:latest mozdef/mozdef_bootstrap:$(BRANCH) && docker push mozdef/mozdef_bootstrap:$(BRANCH) 
	docker tag mozdef/mozdef_alerts:latest mozdef/mozdef_alerts:$(BRANCH) && docker push mozdef/mozdef_alerts:$(BRANCH)
	docker tag mozdef/mozdef_nginx:latest mozdef/mozdef_nginx:$(BRANCH) && docker push mozdef/mozdef_nginx:$(BRANCH)
	docker tag mozdef/mozdef_alertplugins:latest mozdef/mozdef_alertplugins:$(BRANCH) && docker push mozdef/mozdef_alertplugins:$(BRANCH)
	docker tag mozdef/mozdef_rabbitmq:latest mozdef/mozdef_rabbitmq:$(BRANCH) && docker push mozdef/mozdef_rabbitmq:$(BRANCH)
	docker tag mozdef/mozdef_rest:latest mozdef/mozdef_rest:$(BRANCH) && docker push mozdef/mozdef_rest:$(BRANCH)
	docker tag mozdef/mozdef_base:latest mozdef/mozdef_base:$(BRANCH) && docker push mozdef/mozdef_base:$(BRANCH)

docker-get: hub-get
hub-get: ## Download all pre-built images (hub.docker.com/mozdef)
	docker-compose -f docker/compose/docker-compose.yml -p $(NAME) pull
	docker-compose -f docker/compose/docker-compose-test.yml -p test-$(NAME) pull

.PHONY: clean
clean: ## Cleanup all docker volumes and shutdown all related services
	-docker-compose -f docker/compose/docker-compose.yml -p $(NAME) down -v --remove-orphans
	-docker-compose -f docker/compose/docker-compose-tests.yml -p test-$(NAME) down -v --remove-orphans

# Shorthands
.PHONY: rebuild
rebuild: clean build-cwd

.PHONY: new-alert
new-alert: ## Create an example alert and working alert unit test
	python tests/alert_templater.py
