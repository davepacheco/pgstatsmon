#
# Copyright (c) 2018, Joyent, Inc. All rights reserved.
#
# Makefile: pgstatsmon - Postgres monitoring system
#
# This Makefile contains only repo-specific logic and uses included makefiles
# to supply common targets (javascriptlint, jsstyle, restdown, etc.), which are
# used by other repos as well.
#

#
# Tools must be installed on the path
#

JSL	= jsl
JSSTYLE	= jsstyle
CATEST	= deps/catest/catest

#
# Variables
#

NAME	:= pgstatsmon

#
# Prebuilt Node.js
#

NODE_PREBUILT_TAG	= gz
NODE_PREBUILT_IMAGE	= 18b094b0-eb01-11e5-80c1-175dac7ddf02
NODE_PREBUILT_VERSION	= v4.8.7

#
# Files
#

JS_FILES	:= $(shell find bin etc lib test -name '*.js')
JSON_FILES	:= package.json $(shell find etc test -name '*.json')
JSL_FILES_NODE	 = $(JS_FILES)
JSSTYLE_FILES	 = $(JS_FILES)
JSL_CONF_NODE	 = jsl.node.conf

#
# Guard tests from mistakenly being run against production
#

GUARD			 = test/.not_production
DEFAULT_TEST_CONFIG	 = test/etc/testconfig.json
TEST_BACKEND_URL	:= $(shell json -f $(DEFAULT_TEST_CONFIG) static.dbs | json -a ip)

include ./tools/mk/Makefile.defs
include ./tools/mk/Makefile.node_modules.defs
include ./tools/mk/Makefile.node_prebuilt.defs

#
# Install macros and targets
#

PROTO			= proto
PREFIX			= /opt/smartdc/$(NAME)
LIB_FILES		= $(notdir $(wildcard lib/*.js))
ETC_FILES		= $(notdir $(wildcard etc/*.json))
RELEASE_TARBALL		= $(NAME)-pkg-$(STAMP).tar.bz2
NODE_MODULE_INSTALL	= $(PREFIX)/node_modules/.ok

SCRIPTS		= firstboot.sh \
		  everyboot.sh \
		  backup.sh \
		  services.sh \
		  util.sh
SCRIPTS_DIR	= $(PREFIX)/scripts

BOOT_SCRIPTS		= setup.sh configure.sh
BOOT_SCRIPTS_DIR	= /opt/smartdc/boot

NODE_BITS	= bin/node \
		  lib/libgcc_s.so.1 \
		  lib/libstdc++.so.6
NODE_BITS_DIR	= $(PREFIX)/node

SAPI_MANIFESTS		= pgstatsmon
SAPI_MANIFESTS_DIRS	= $(SAPI_MANIFESTS:%=$(PREFIX)/sapi_manifests/%)

SMF_MANIFEST		= pgstatsmon
SMF_MANIFEST_DIR	= $(PREFIX)/smf/manifests

DTRACE_SCRIPTS		= backendstat.d querystat.d walstat.d
DTRACE_SCRIPTS_DIR	= $(PREFIX)/bin/dtrace

INSTALL_FILES	= $(addprefix $(PROTO), \
		  $(PREFIX)/bin/pgstatsmon.js \
		  $(DTRACE_SCRIPTS:%=$(DTRACE_SCRIPTS_DIR)/%) \
		  $(BOOT_SCRIPTS:%=$(BOOT_SCRIPTS_DIR)/%) \
		  $(SCRIPTS:%=$(SCRIPTS_DIR)/%) \
		  $(LIB_FILES:%=$(PREFIX)/lib/%) \
		  $(ETC_FILES:%=$(PREFIX)/etc/%) \
		  $(NODE_MODULE_INSTALL) \
		  $(NODE_BITS:%=$(NODE_BITS_DIR)/%) \
		  $(BOOT_SCRIPTS:%=$(BOOT_SCRIPTS_DIR)/%) \
		  $(SAPI_MANIFESTS_DIRS:%=%/template) \
		  $(SAPI_MANIFESTS_DIRS:%=%/manifest.json) \
		  $(SMF_MANIFEST:%=$(SMF_MANIFEST_DIR)/%.xml) \
		  )

INSTALL_DIRS	= $(addprefix $(PROTO), \
		  $(PREFIX)/bin \
		  $(PREFIX)/bin/dtrace \
		  $(PREFIX)/lib \
		  $(PREFIX)/etc \
		  $(SCRIPTS_DIR) \
		  $(NODE_BITS_DIR) \
		  $(NODE_BITS_DIR)/bin \
		  $(NODE_BITS_DIR)/lib \
		  $(BOOT_SCRIPTS_DIR) \
		  $(SMF_MANIFEST_DIR) \
		  $(SAPI_MANIFESTS_DIRS) \
		  )

INSTALL_FILE = rm -f $@ && cp $< $@ && chmod 644 $@
INSTALL_EXEC = rm -f $@ && cp $< $@ && chmod 755 $@

#
# build targets
#

.PHONY: all
all: $(STAMP_NODE_PREBUILT) $(STAMP_NODE_MODULES)
	$(NODE) --version

.PHONY: install
install: $(INSTALL_FILES)

.PHONY: release
release: install
	@echo "==> Building $(RELEASE_TARBALL)"
	cd $(PROTO) && gtar -jcf $(TOP)/$(RELEASE_TARBALL) \
		--transform='s,^[^.],root/&,' \
		--owner=0 --group=0 \
		opt

.PHONY: publish
publish: release
	@if [[ -z "$(BITS_DIR)" ]]; then \
		echo "error: 'BITS_DIR' must be set for 'publish' target"; \
		exit 1; \
	fi
	mkdir -p $(BITS_DIR)/$(NAME)
	cp $(RELEASE_TARBALL) $(BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)

.PHONY: test
test: $(GUARD) all
	$(CATEST) test/*.tst.js

$(GUARD):
	@echo

	@echo "Test configuration is pointed at $(TEST_BACKEND_URL)."
	@echo
	@echo "Verify that this is _not_ a production database and create \
	the blank file:"
	@echo
	@echo "\t$(GUARD)"
	@echo
	@echo "Tests will not run until this file is present."

	@echo
	@exit 1

# 'install' targets for each file, or set of files
$(INSTALL_DIRS):
	mkdir -p $@

$(PROTO)$(PREFIX)/bin/%.js: bin/%.js | $(INSTALL_DIRS)
	$(INSTALL_FILE)

$(PROTO)$(DTRACE_SCRIPTS_DIR)/%.d: bin/dtrace/%.d | $(INSTALL_DIRS)
	$(INSTALL_EXEC)

$(PROTO)$(PREFIX)/lib/%: lib/% | $(INSTALL_DIRS)
	$(INSTALL_FILE)

$(PROTO)$(PREFIX)/etc/%: etc/% | $(INSTALL_DIRS)
	$(INSTALL_FILE)

# copy node_modules into PROTO dir, and create touch file to signify 'done'
$(PROTO)$(NODE_MODULE_INSTALL): $(STAMP_NODE_MODULES) | $(INSTALL_DIRS)
	rm -rf $(@D)/
	cp -rP node_modules/ $(@D)/
	touch $@

# copy the node binary into the PROTO dir
$(PROTO)$(PREFIX)/node/bin/%: $(STAMP_NODE_PREBUILT) | $(INSTALL_DIRS)
	rm -f $@ && cp $(NODE_INSTALL)/bin/$(@F) $@ && chmod 755 $@

# copy node's linked libraries into the PROTO dir
$(PROTO)$(PREFIX)/node/lib/%: $(STAMP_NODE_PREBUILT) | $(INSTALL_DIRS)
	rm -f $@ && cp $(NODE_INSTALL)/lib/$(@F) $@ && chmod 755 $@

# install the boot scripts
$(PROTO)$(BOOT_SCRIPTS_DIR)/setup.sh: | $(INSTALL_DIRS)
	rm -f $@ && ln -s ../$(NAME)/scripts/firstboot.sh $@

$(PROTO)$(BOOT_SCRIPTS_DIR)/configure.sh: | $(INSTALL_DIRS)
	rm -f $@ && ln -s ../$(NAME)/scripts/everyboot.sh $@

$(PROTO)$(PREFIX)/scripts/%.sh: deps/manta-scripts/%.sh | $(INSTALL_DIRS)
	$(INSTALL_EXEC)

$(PROTO)$(PREFIX)/scripts/%.sh: boot/%.sh | $(INSTALL_DIRS)
	$(INSTALL_EXEC)

# install sapi manifests
$(PROTO)$(PREFIX)/sapi_manifests/%: sapi_manifests/% | $(INSTALL_DIRS)
	$(INSTALL_FILE)

# install SMF manifests
$(PROTO)$(PREFIX)/smf/manifests/%: smf/manifests/% | $(INSTALL_DIRS)
	$(INSTALL_FILE)

include ./tools/mk/Makefile.targ
include ./tools/mk/Makefile.node_modules.targ
include ./tools/mk/Makefile.node_prebuilt.targ
