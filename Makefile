# Build cgit
#
RPMBUILD = /usr/bin/rpmbuild
GIT = /usr/bin/git
SED = /bin/sed

CGIT_PKG = cgit
CGIT_BRANCH = v0.11.2.1bbp
CGIT_VERSION := $(shell $(GIT) describe --abbrev=0 $(CGIT_BRANCH) | $(SED) -e 's/^v//' -e 's/-/./g')
CGIT_RELEASE = 1
CGIT_DIST = el6

GIT_VERSION = 1.9.0
GIT_DOWNLOAD = http://git-core.googlecode.com/files/git-$(GIT_VERSION).tar.gz

BUILD_DIR = build
SPEC_NAME = $(BUILD_DIR)/$(CGIT_PKG).spec
CONF_NAME = $(BUILD_DIR)/cgitrc
TGZ_NAME  = $(BUILD_DIR)/$(CGIT_PKG)-$(CGIT_VERSION).tar.gz
GIT_TGZ   = $(BUILD_DIR)/git-$(GIT_VERSION).tar.gz
SRPM_NAME = $(BUILD_DIR)/$(CGIT_PKG)-$(CGIT_VERSION)-$(CGIT_RELEASE).src.rpm
RPM_NAME  = $(BUILD_DIR)/$(CGIT_PKG)-$(CGIT_VERSION)-$(CGIT_RELEASE).$(CGIT_DIST).rpm

.PHONY: setup tgz srpm rpm clean

all: rpm

tgz: $(TGZ_NAME)
srpm: $(SRPM_NAME)
rpm: $(RPM_NAME)

$(TGZ_NAME): $(BUILD_DIR)
	$(GIT) fetch --all --prune
	$(GIT) fetch origin $(CGIT_BRANCH):$(CGIT_BRANCH)
	$(GIT) archive --format=tar --prefix=$(CGIT_PKG)-$(CGIT_VERSION)/ \
		$(CGIT_BRANCH) | gzip > $(TGZ_NAME)

$(SPEC_NAME): $(CGIT_PKG).spec
	$(SED)  -e 's|@@VERSION@@|$(CGIT_VERSION)|g' \
		-e 's|@@RELEASE@@|$(CGIT_RELEASE)|g' \
		-e 's|@@GIT_VERSION@@|$(GIT_VERSION)|g' \
		$(CGIT_PKG).spec > $(SPEC_NAME)

$(GIT_TGZ): $(BUILD_DIR)
	curl $(GIT_DOWNLOAD) > $(GIT_TGZ)

$(CONF_NAME): $(BUILD_DIR)
	cp cgitrc $(CONF_NAME)

$(SRPM_NAME): $(TGZ_NAME) $(SPEC_NAME) $(GIT_TGZ) $(CONF_NAME)
	$(RPMBUILD) -bs --nodeps \
		--define "_tmppath /tmp" \
		--define "_sourcedir $(BUILD_DIR)" \
		--define "_srcrpmdir $(BUILD_DIR)" \
		--define 'dist %{nil}' \
		$(SPEC_NAME)

$(RPM_NAME): $(SRPM_NAME)
	$(RPMBUILD) --rebuild $(SRPM_NAME)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

setup: $(BUILD_DIR)
	rpmdev-setuptree

clean:
	rm -rf $(BUILD_DIR)

