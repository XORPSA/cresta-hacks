BRANCH ?=$(shell cat BRANCH)
GITHUB_ACTOR ?=$(shell cat GITHUB_ACTOR)
ECR_URL=242659714806.dkr.ecr.us-west-2.amazonaws.com/cresta/chat-ai/core

# construct environment for notebook
ENVIRONMENT ?=voice-staging
AWS_REGION_OVERRIDE ?=us-west-2
ifeq (staging, $(findstring staging, $(ENVIRONMENT)))
  JWT_SECRET_API_OVERRIDE='$(shell aws --profile 'us-west-2-staging_ro' secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/cresta-server-jwt_secret-staging-NFJItz' --query SecretString --output text | docker run --rm -i mikefarah/yq:3.4.1 yq read - jwt-secret)'
else ifeq (us-east-1-prod, $(ENVIRONMENT))
  AWS_REGION_OVERRIDE=us-east-1
  JWT_SECRET_API_OVERRIDE='$(shell aws --profile 'us-east-1-prod_ro' secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:us-east-1:242659714806:secret:shared/cresta-server-jwt_secret-us-east-1-prod-axvbL7' --query SecretString --output text | docker run --rm -i mikefarah/yq:3.4.1 yq read - jwt-secret)'
else
  JWT_SECRET_API_OVERRIDE='$(shell aws --profile "us-west-2-prod_ro" secretsmanager get-secret-value --secret-id "arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/cresta-server-jwt_secret-VDn5My" --query SecretString --output text | docker run --rm -i mikefarah/yq:3.4.1 yq read - jwt-secret)'
endif
ifeq (staging, $(findstring staging, $(ENVIRONMENT)))
  OPENAI_API_KEY_OVERRIDE='$(shell aws --profile 'infra-prod_ro' secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/openai-gpt3-api-key' --query SecretString --output text)'
else
  OPENAI_API_KEY_OVERRIDE='$(shell aws --profile 'infra-prod_ro' secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/openai-gpt3-api-key-prod' --query SecretString --output text | docker run --rm -i mikefarah/yq:3.4.1 yq read - apiKey)'
endif

# use gsed if MacOS (brew install gnu-sed)
SED := $(shell command -v gsed || command -v sed)

.PHONY: all note-classic note note-mac note-voice install full-install install-dev test test-uv db clean load-test install-sys-packages install-deps get-requirements

clean:
	pip freeze | grep -v "-e " | xargs pip uninstall -y
	pip uninstall -y greyparrot cresta-common feature-store
	find . -name '*.pyc' -delete

install:
	pip install --upgrade pip==22.3.1
	pip install -U setuptools==69.5.1
	pip install -e vendor/cresta-common
	pip install cython

spacy_installed := $(shell bash -c "echo -e 'try:\n  import spacy\n  print(\"yes\")\nexcept ImportError:\n  print(\"no\")' | python -")
nltk_installed := $(shell bash -c "echo -e 'try:\n  import nltk\n  print(\"yes\")\nexcept ImportError:\n  print(\"no\")' | python -")
post-install:
	if [ "$(spacy_installed)" = "yes" ]; then python -m spacy download en_core_web_sm; python -m spacy download en_core_web_trf_ner_ft; python -m spacy download fr_core_news_sm; python -m spacy download de_core_news_sm; python -m spacy download es_core_news_sm; fi
	if [ "$(nltk_installed)" = "yes" ]; then python -m nltk.downloader wordnet punkt_tab stopwords omw-1.4; fi
  # onnxruntime-gpu does not support MacOS, so we install it in post-install so that greyparrot can be installed on MacOS
	pip install onnxruntime-gpu==1.14.1 || true

full-install: install post-install

install-greyparrot-full:
	pip install -e .[full] -c constraints.txt

install-greyparrot-base:
	pip install -e .[common,config,grpc-api,multi-tenancy,utils] -c constraints.txt

install-dev: install install-greyparrot-full post-install

install-dev-base: install install-greyparrot-base

get-requirements:
	python -c 'from setup import get_requirements; print("\n".join(get_requirements()["full"]))' > .tmp-requirements-full.txt

install-deps: get-requirements
	pip install -r .tmp-requirements-full.txt -r app/chat-ai/requirements.txt -c constraints.txt

install-deps-uv: get-requirements
	uv pip install -r .tmp-requirements-full.txt -r app/chat-ai/requirements.txt -c constraints.txt --index-url="$$(pip config get global.index-url)"

install-sys-packages:
	@echo "Checking operating system..."
	@if command -v lsb_release >/dev/null 2>&1; then \
		distro=$$(lsb_release -i | awk '{print $$3}'); \
		if [ "$$distro" = "Ubuntu" ]; then \
			sudo apt-get update; \
			sudo apt-get install redis-server libxml2 wget build-essential libpq-dev libsqlite3-dev postgresql postgresql-contrib -y; \
			sudo apt-get upgrade openssl -y; \
		else \
			echo "This system is running Linux, but not Ubuntu."; \
			exit 1; \
		fi \
	elif [ "$$(uname)" = "Darwin" ]; then \
		echo "This system is running macOS."; \
	else \
		echo "This system is not running Ubuntu or macOS."; \
		exit 1; \
	fi

update-constraints:
	# pip install pip-tools
	pip-compile --extra full --strip-extras --no-emit-index-url --output-file constraints.txt setup.py --verbose $${PIP_COMPILE_ARGS:-}

update-constraints-uv: get-requirements
	uv pip compile --strip-extras --no-emit-index-url --output-file constraints.txt .tmp-requirements-full.txt app/chat-ai/requirements.txt  --index-url="$$(pip config get global.index-url)" --verbose $${PIP_COMPILE_ARGS:-}

bump-version:
	@read -p "Enter the package name (e.g. crestaproto): " package_name; \
	read -p "Enter the new package name version (e.g. 1.0.2): " new_version; \
	echo "Bumping version for package '$$package_name' to '$$new_version'"; \
	SED_CMD="sed"; \
	if [ "$$(uname)" = "Darwin" ]; then \
		SED_CMD="gsed"; \
		if [ "$$(command -v gsed)" = "" ]; then \
			read -p "gsed not found, but required. Install gnu-sed using Homebrew? (y/N) " install_gsed; \
			if [[ "$$install_gsed" =~ ^[Yy]$$ ]]; then \
				echo "Installing gnu-sed using Homebrew..."; \
				brew install gnu-sed; \
				SED_CMD="gsed"; \
			else \
				echo "Please install 'gsed' using 'brew install gnu-sed'"; \
				exit 1; \
			fi; \
		fi; \
	fi; \
	find . -type f -name 'requirements*.txt' -exec $$SED_CMD -i 's/^s*\('"$$package_name"'\(>\|=\|~\)=\)[^ ]*/\1'"$$new_version"'/g' {} +

note-classic:
	# Installs all jupyter notebook extensions
	jupyter contrib nbextensions install --sys-prefix --skip-running-check
	# Enables the Nbextensions tab
	#   Uncheck from Nbextensions tab: "disable configuration for nbextensions without explicit compatibility"
	#   and then enable/disable extensions as needed from the UI
	#   https://github.com/Jupyter-contrib/jupyter_nbextensions_configurator/issues/103
	jupyter nbextensions_configurator enable --user
	# Two recommended extensions
	jupyter nbextension enable --sys-prefix collapsible_headings/main
	PYTHONPATH=$(PWD) jupyter notebook --ip 0.0.0.0 --port 80 --allow-root

note:
	# Add default settings to Jupyter Lab (REMOVED
	# https://jupyterlab.readthedocs.io/en/stable/user/directories.html#overrides-json
	# chmod +x bin/copy-settings-overrides-json-for-jupyterlab.sh
	# bin/copy-settings-overrides-json-for-jupyterlab.sh
	AWS_REGION=$(AWS_REGION_OVERRIDE) \
	CONFIG_SERVICE_ADDR='auth.$(ENVIRONMENT).internal.cresta.ai:443' \
    CONFIG_USE_SECURE_CHANNEL='true' \
	READ_DEFAULT_LLM_SERVING_CONFIG_FROM_K8S='true' \
	ACCESS_DB_USING_IAM='true' \
	JWT_SECRET_API=$(JWT_SECRET_API_OVERRIDE) \
	LLM_PROXY_PROJECT_ID='notebook' \
	LLM_PROXY_BASE_URL='http://api-exampleappenv.$(ENVIRONMENT).internal.cresta.ai' \
	OPENAI_API_KEY=$(OPENAI_API_KEY_OVERRIDE) \
	PYTHONPATH=$(PWD) jupyter-lab --ip 0.0.0.0 --port 8888 --allow-root --NotebookApp.iopub_data_rate_limit=1.0e10 --NotebookApp.iopub_msg_rate_limit=1.0e10 --NotebookApp.rate_limit_window=10

note-local:
	# for local development (not dev server)
	CONFIG_SERVICE_ADDR='auth.$(ENVIRONMENT).internal.cresta.ai:443' \
        CONFIG_USE_SECURE_CHANNEL='true' \
	ACCESS_DB_USING_IAM='true' \
	JWT_SECRET_API='$(shell aws --profile "chat-prod_ro" secretsmanager get-secret-value --secret-id "arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/cresta-server-jwt_secret-VDn5My" --query SecretString --output text | docker run --rm -i mikefarah/yq:3.4.1 yq read - jwt-secret)' \
        LLM_PROXY_PROJECT_ID='notebook' \
	LLM_PROXY_BASE_URL='http://api-exampleappenv.chat-staging.internal.cresta.ai' \
	PYTHONPATH=$(PWD) jupyter-lab --NotebookApp.iopub_data_rate_limit=1.0e10 --NotebookApp.iopub_msg_rate_limit=1.0e10 --NotebookApp.rate_limit_window=10

db:
	echo 'Spinning up temporary database'
	docker-compose run --rm --publish 5432:5432 db

test:
	find . -iname "*.pyc" -exec rm -rf {} \; || true
	find . -iname "*.pyo" -exec rm -rf {} \; || true
	find . -name "__pycache__" -exec rm -rf {} \; || true
	pip install -r requirements-test.txt -c constraints.txt

	docker-compose up --abort-on-container-exit &
	docker ps

	if [ "$(RUNNING_IN_CI)" = "true" ]; then \
		BRANCH=${BRANCH} \
		APP_ENV=test \
		TEST_PGHOST=localhost \
		AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
		AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
		AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN} \
		AWS_REGION=us-west-2 \
		S3_ENDPOINT=s3.us-west-2.amazonaws.com \
		TESTFILES="${TESTFILES}" \
		RUNNING_IN_CI=${RUNNING_IN_CI} \
		CHAT_PROD_PROFILE_DOCKER=chat-prod \
		ENABLE_TESTMON=${ENABLE_TESTMON} \
		HF_TOKEN=${HF_TOKEN} \
		REDIS_ADDRESS=localhost \
		./bin/wait-for-it.sh localhost:5432 -- ./bin/get-testmondata.sh; \
	else \
		AWS_PROFILE=cresta-pci-account_dev \
		TEST_PGHOST=localhost \
		APP_ENV=test \
		REDIS_ADDRESS=localhost \
		./bin/wait-for-it.sh localhost:5432 -- pytest -s tests; \
	fi

	docker-compose down

test-uv:
	find . -iname "*.pyc" -exec rm -rf {} \; || true
	find . -iname "*.pyo" -exec rm -rf {} \; || true
	find . -name "__pycache__" -exec rm -rf {} \; || true
	uv pip install -r requirements-test.txt -c constraints.txt --index-url="$$(pip config get global.index-url)"

	docker-compose up --abort-on-container-exit &
	docker ps

	if [ "$(RUNNING_IN_CI)" = "true" ]; then \
		BRANCH=${BRANCH} \
		APP_ENV=test \
		TEST_PGHOST=localhost \
		AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
		AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
		AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN} \
		AWS_REGION=us-west-2 \
		S3_ENDPOINT=s3.us-west-2.amazonaws.com \
		TESTFILES="${TESTFILES}" \
		RUNNING_IN_CI=${RUNNING_IN_CI} \
		CHAT_PROD_PROFILE_DOCKER=chat-prod \
		ENABLE_TESTMON=${ENABLE_TESTMON} \
		HF_TOKEN=${HF_TOKEN} \
		REDIS_ADDRESS=localhost \
		./bin/wait-for-it.sh localhost:5432 -- ./bin/get-testmondata.sh; \
	else \
		AWS_PROFILE=cresta-pci-account_dev \
		TEST_PGHOST=localhost \
		APP_ENV=test \
		REDIS_ADDRESS=localhost \
		./bin/wait-for-it.sh localhost:5432 -- pytest -s tests; \
	fi

	docker-compose down

sshkeys:
	mkdir -p ~/.ssh/devserver
	gpg --output ~/.ssh/devserver/crestalabs.com.zip --decrypt crestalabs.com.zip.gpg
	cd ~/.ssh/devserver/ && unzip crestalabs.com.zip

format:
	yapf -ir greyparrot
	yapf -ir tests

load-test:
	locust -f load-testing-scripts/load-test-api-suggestions.py \
        --headless --users 100 --hatch-rate 10 --run-time 100s \
        --host https://cox.staging2002.cresta.com

test-local-setup:
	docker-compose -f docker-compose-localtest.yaml up --detach
	docker ps
	./bin/wait-for-it.sh localhost:5432 -t 60

test-local:
	find . -iname "*.pyc" -exec rm -rf {} \; || true
	find . -iname "*.pyo" -exec rm -rf {} \; || true
	find . -name "__pycache__" -exec rm -rf {} \; || true
	AWS_PROFILE=cresta-pci-account_dev TEST_PGHOST=localhost APP_ENV=test REDIS_ADDRESS=localhost py.test -s tests

test-local-no-skip:
	find . -iname "*.pyc" -exec rm -rf {} \; || true
	find . -iname "*.pyo" -exec rm -rf {} \; || true
	find . -name "__pycache__" -exec rm -rf {} \; || true
	# AWS_PROFILE=cresta-pci-account_dev TEST_PGHOST=localhost APP_ENV=test REDIS_ADDRESS=localhost RUN_NON_HERMETIC=1 CONFIG_SERVICE_ADDR='auth.chat-prod.internal.cresta.ai:443' CONFIG_USE_SECURE_CHANNEL=true USE_MOCK_CONFIG_SERVICE=false JWT_SECRET_API_OVERRIDE="$(aws --profile 'chat-prod_ro' secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:us-west-2:242659714806:secret:shared/cresta-server-jwt_secret-VDn5My' --query SecretString --output text | yq .jwt-secret -)"  py.test -s tests
	AWS_PROFILE=cresta-pci-account_dev TEST_PGHOST=localhost APP_ENV=test REDIS_ADDRESS=localhost RUN_NON_HERMETIC=1 ACCESS_DB_USING_IAM=true py.test -s tests --no-skips

test-local-teardown:
	docker-compose -f docker-compose-localtest.yaml down
