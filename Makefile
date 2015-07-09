# Build cgit
#
SHELL := /bin/bash
MOCK = /usr/bin/mock
CURL = /usr/bin/curl
GIT = /usr/bin/git
SED = /bin/sed
TAR = /bin/tar

PACKAGE_NAME = cgit
PACKAGE_BRANCH = v0.11.2.1bbp
PACKAGE_VERSION := $(shell $(GIT) describe --abbrev=0 $(PACKAGE_BRANCH) | $(SED) -e 's/^v//' -e 's/-/./g')
PACKAGE_RELEASE = 1

GIT_VERSION = 2.3.2
GIT_DOWNLOAD = https://www.kernel.org/pub/software/scm/git/git-$(GIT_VERSION).tar.gz

RPM_DIST = el6
RPM_PLATFORM = x86_64
MOCK_PROFILE = rhel-6-$(RPM_PLATFORM)

SRC_DIR = src
OUTPUT_DIR = artifacts
SRPM_DIR = $(OUTPUT_DIR)/srpm
RPM_DIR = $(OUTPUT_DIR)/rpm
PACKAGE_SRC_DIR = $(SRC_DIR)/$(PACKAGE_NAME)

SPEC_NAME = $(PACKAGE_NAME).spec
GIT_TGZ   = git-$(GIT_VERSION).tar.gz
TGZ_NAME  = $(PACKAGE_NAME)-$(PACKAGE_VERSION).tar.bz2
SRPM_NAME = $(SRPM_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)-$(PACKAGE_RELEASE).$(RPM_DIST).src.rpm

MOCK_BUILD = $(RPM_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)-$(PACKAGE_RELEASE).$(RPM_DIST).$(RPM_PLATFORM).rpm

SRC_FILES = \
	$(TGZ_NAME) \
	$(GIT_TGZ) \
	cgitrc

.PHONY: setup tbz srpm mock clean

all: mock

tbz: $(TGZ_NAME)
srpm: $(SRPM_NAME)
mock: $(MOCK_BUILD)

$(PACKAGE_SRC_DIR): | $(SRC_DIR)
	$(GIT) clone --shared . $(PACKAGE_SRC_DIR)
	pushd $(PACKAGE_SRC_DIR); \
	$(GIT) checkout $(PACKAGE_BRANCH); \
	$(GIT) submodule update --init; \
	popd

$(TGZ_NAME): $(PACKAGE_SRC_DIR)
	$(TAR) --transform 's,$(PACKAGE_SRC_DIR),$(PACKAGE_NAME)-$(PACKAGE_VERSION),S' \
	--exclude .git \
	--exclude .gitignore \
	--exclude .gitmodules \
	-c -j -f $(TGZ_NAME) $(PACKAGE_SRC_DIR)

$(GIT_TGZ): $(BUILD_DIR)
	$(CURL) $(GIT_DOWNLOAD) > $(GIT_TGZ)

$(SRPM_NAME): $(SRC_FILES) | $(OUTPUT_DIR)
	$(MOCK) -r $(MOCK_PROFILE) --configdir=. --buildsrpm \
	--resultdir=$(SRPM_DIR) \
	--sources=. \
	--spec $(SPEC_NAME)

$(MOCK_BUILD): $(SRPM_NAME) | $(OUTPUT_DIR)
	$(MOCK) -r $(MOCK_PROFILE) --configdir=. \
	--resultdir=$(RPM_DIR) \
	$(SRPM_NAME)

$(SRC_DIR):
	mkdir -p $(SRC_DIR)

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)
	mkdir -p $(SRPM_DIR)
	mkdir -p $(RPM_DIR)

clean:
	rm -rf $(SRC_DIR)
	rm -rf $(OUTPUT_DIR)
	rm -f $(GIT_TGZ)
	rm -f $(TGZ_NAME)
	rm -f $(SRPM_NAME)

