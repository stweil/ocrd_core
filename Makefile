export

SHELL = /bin/bash
PYTHON ?= python
PIP ?= pip
LOG_LEVEL = INFO
PYTHONIOENCODING=utf8
TESTDIR = tests

SPHINX_APIDOC =

BUILD_ORDER = ocrd_utils ocrd_models ocrd_modelfactory ocrd_validators ocrd_network ocrd
reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))

PEP_440_PATTERN := '([1-9][0-9]*!)?(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*((a|b|rc)(0|[1-9][0-9]*))?(\.post(0|[1-9][0-9]*))?(\.dev(0|[1-9][0-9]*))?'
OCRD_VERSION != fgrep version= ocrd_utils/setup.py | grep -Po $(PEP_440_PATTERN)

# BEGIN-EVAL makefile-parser --make-help Makefile

help:
	@echo ""
	@echo "  Targets"
	@echo ""
	@echo "    deps-ubuntu    Dependencies for deployment in an ubuntu/debian linux"
	@echo "    deps-test      Install test python deps via pip"
	@echo "    install        (Re)install the tool"
	@echo "    install-dev    Install with pip install -e"
	@echo "    uninstall      Uninstall the tool"
	@echo "    generate-page  Regenerate python code from PAGE XSD"
	@echo "    spec           Copy JSON Schema, OpenAPI from OCR-D/spec"
	@echo "    assets         Setup test assets"
	@echo "    test           Run all unit tests"
	@echo "    docs           Build documentation"
	@echo "    docs-clean     Clean docs"
	@echo "    docs-coverage  Calculate docstring coverage"
	@echo "    docker         Build docker image"
	@echo "    docker-cuda    Build docker GPU / CUDA image"
	@echo "    cuda-ubuntu    Install native CUDA toolkit in different versions"
	@echo "    pypi           Build wheels and source dist and twine upload them"
	@echo ""
	@echo "  Variables"
	@echo ""
	@echo "    DOCKER_TAG         Docker tag. Default: '$(DOCKER_TAG)'."
	@echo "    DOCKER_BASE_IMAGE  Docker base image. Default: '$(DOCKER_BASE_IMAGE)'."
	@echo "    DOCKER_ARGS        Additional arguments to docker build. Default: '$(DOCKER_ARGS)'"
	@echo "    PIP_INSTALL        pip install command. Default: $(PIP_INSTALL)"

# END-EVAL

# Docker tag. Default: '$(DOCKER_TAG)'.
DOCKER_TAG = ocrd/core

# Docker base image. Default: '$(DOCKER_BASE_IMAGE)'.
DOCKER_BASE_IMAGE = ubuntu:20.04

# Additional arguments to docker build. Default: '$(DOCKER_ARGS)'
DOCKER_ARGS = 

# pip install command. Default: $(PIP_INSTALL)
PIP_INSTALL = $(PIP) install

# Dependencies for deployment in an ubuntu/debian linux
deps-ubuntu:
	apt-get install -y python3 imagemagick libgeos-dev

# Install test python deps via pip
deps-test:
	$(PIP) install -U pip
	$(PIP) install -r requirements_test.txt

# (Re)install the tool
install:
	$(PIP) install -U pip wheel setuptools fastentrypoints
	@# speedup for end-of-life builds
	if $(PYTHON) -V | fgrep -e 3.5 -e 3.6; then $(PIP) install --prefer-binary opencv-python-headless numpy; fi
#	$(PIP_INSTALL) $(BUILD_ORDER:%=./%/dist/ocrd$*(OCRD_VERSION)*.whl)
	$(foreach MODULE,$(BUILD_ORDER),$(PIP_INSTALL) ./$(MODULE) &&) echo done
	@# workaround for shapely#1598
	$(PIP) install --no-binary shapely --force-reinstall shapely

# Install with pip install -e
install-dev: uninstall
	$(MAKE) install PIP_INSTALL="$(PIP) install -e"

# Uninstall the tool
uninstall:
	$(PIP) uninstall -y $(call reverse,$(BUILD_ORDER))

# Regenerate python code from PAGE XSD
generate-page: GDS_PAGE = ocrd_models/ocrd_models/ocrd_page_generateds.py
generate-page: GDS_PAGE_USER = ocrd_models/ocrd_page_user_methods.py
generate-page: repo/assets
	generateDS \
		-f \
		--root-element='PcGts' \
		-o $(GDS_PAGE) \
		--silence \
		--export "write etree" \
		--disable-generatedssuper-lookup \
		--user-methods=$(GDS_PAGE_USER) \
		ocrd_validators/ocrd_validators/page.xsd
	# hack to prevent #451: enum keys will be strings
	sed -i 's/(Enum):$$/(str, Enum):/' $(GDS_PAGE)
	# hack to ensure output has pc: prefix
	@#sed -i "s/namespaceprefix_=''/namespaceprefix_='pc:'/" $(GDS_PAGE)
	sed -i 's/_nsprefix_ = None/_nsprefix_ = "pc"/' $(GDS_PAGE)
	# hack to ensure child nodes also have pc: prefix...
	sed -i 's/.*_nsprefix_ = child_.prefix$$//' $(GDS_PAGE)
	# replace the need for six since we target python 3.6+
	sed -i 's/from six.moves/from itertools/' $(GDS_PAGE)

#
# Repos
#
.PHONY: repos always-update
repos: repo/assets repo/spec


# Update OCR-D/assets and OCR-D/spec resp.
repo/assets repo/spec: always-update
	git submodule sync --recursive $@
	if git submodule status --recursive $@ | grep -qv '^ '; then \
		git submodule update --init --recursive $@ && \
		touch $@; \
	fi

#
# Spec
#

.PHONY: spec
# Copy JSON Schema, OpenAPI from OCR-D/spec
spec: repo/spec
	cp repo/spec/ocrd_tool.schema.yml ocrd_validators/ocrd_validators/ocrd_tool.schema.yml
	cp repo/spec/bagit-profile.yml ocrd_validators/ocrd_validators/bagit-profile.yml

#
# Assets
#

# Setup test assets
assets: repo/assets
	rm -rf $(TESTDIR)/assets
	mkdir -p $(TESTDIR)/assets
	cp -r repo/assets/data/* $(TESTDIR)/assets


#
# Tests
#

.PHONY: test
# Run all unit tests
test: assets
	HOME=$(CURDIR)/ocrd_utils $(PYTHON) -m pytest --continue-on-collection-errors -k TestLogging $(TESTDIR)
	HOME=$(CURDIR) $(PYTHON) -m pytest --continue-on-collection-errors -k TestLogging $(TESTDIR)
	$(PYTHON) -m pytest --continue-on-collection-errors --durations=10 --ignore=$(TESTDIR)/test_logging.py --ignore-glob="$(TESTDIR)/**/*bench*.py" $(TESTDIR)

benchmark:
	$(PYTHON) -m pytest $(TESTDIR)/model/test_ocrd_mets_bench.py

benchmark-extreme:
	$(PYTHON) -m pytest $(TESTDIR)/model/*bench*.py

test-profile:
	$(PYTHON) -m cProfile -o profile $$(which pytest)
	$(PYTHON) analyze_profile.py

coverage: assets
	coverage erase
	make test PYTHON="coverage run"
	coverage report
	coverage html

#
# Documentation
#

.PHONY: docs
# Build documentation
docs:
	for mod in $(BUILD_ORDER);do sphinx-apidoc -f -M -e \
		-o docs/api/$$mod $$mod/$$mod \
		'ocrd_models/ocrd_models/ocrd_page_generateds.py' \
		;done
	cd docs ; $(MAKE) html

docs-push: gh-pages docs
	cp -r docs/build/html/* gh-pages
	cd gh-pages; git add . && git commit -m 'Updated docs $$(date)' && git push

# Clean docs
docs-clean:
	cd gh-pages ; rm -rf *
	cd docs ; rm -rf _build api/ocrd api/ocrd_*

# Calculate docstring coverage
docs-coverage:
	for mod in $(BUILD_ORDER);do docstr-coverage $$mod/$$mod -e '.*(ocrd_page_generateds|/ocrd/cli/).*';done
	for mod in $(BUILD_ORDER);do echo "# $$mod"; docstr-coverage -v1 $$mod/$$mod -e '.*(ocrd_page_generateds|/ocrd/cli/).*'|sed 's/^/\t/';done

gh-pages:
	git clone --branch gh-pages https://github.com/OCR-D/core gh-pages

#
# Clean up
#

pyclean:
	rm -f **/*.pyc
	find . -name '__pycache__' -exec rm -rf '{}' \;
	rm -rf .pytest_cache

#
# Docker
#

.PHONY: docker docker-cuda

# Build docker image
docker docker-cuda:
	docker build -t $(DOCKER_TAG) --build-arg BASE_IMAGE=$(DOCKER_BASE_IMAGE) $(DOCKER_ARGS) .

# Build docker GPU / CUDA image
docker-cuda: DOCKER_BASE_IMAGE = nvidia/cuda:11.3.1-cudnn8-runtime-ubuntu20.04
docker-cuda: DOCKER_TAG = ocrd/core-cuda
docker-cuda: DOCKER_ARGS += --build-arg FIXUP="make cuda-ubuntu cuda-ldconfig"

#
# CUDA
#

.PHONY: cuda-ubuntu cuda-ldconfig

# Install native CUDA toolkit in different versions
cuda-ubuntu: cuda-ldconfig
	apt-get -y install --no-install-recommends cuda-runtime-11-0 cuda-runtime-11-1 cuda-runtime-11-3 cuda-runtime-11-7 cuda-runtime-12-1

cuda-ldconfig: /etc/ld.so.conf.d/cuda.conf
	ldconfig

/etc/ld.so.conf.d/cuda.conf:
	@echo > $@
	@echo /usr/local/cuda-11.0/lib64 >> $@
	@echo /usr/local/cuda-11.0/targets/x86_64-linux/lib >> $@
	@echo /usr/local/cuda-11.1/lib64 >> $@
	@echo /usr/local/cuda-11.1/targets/x86_64-linux/lib >> $@
	@echo /usr/local/cuda-11.3/lib64 >> $@
	@echo /usr/local/cuda-11.3/targets/x86_64-linux/lib >> $@
	@echo /usr/local/cuda-11.7/lib64 >> $@
	@echo /usr/local/cuda-11.7/targets/x86_64-linux/lib >> $@
	@echo /usr/local/cuda-12.1/lib64 >> $@
	@echo /usr/local/cuda-12.1/targets/x86_64-linux/lib >> $@

# Build wheels and source dist and twine upload them
pypi: uninstall install
	$(PIP) install build
	$(foreach MODULE,$(BUILD_ORDER),$(PYTHON) -m build -n ./$(MODULE) &&) echo done
	twine upload ocrd*/dist/ocrd*$(OCRD_VERSION)*{tar.gz,whl}
