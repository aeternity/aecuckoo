UNAME_S = $(shell uname -s)

EXECUTABLES = \
	mean29-generic \
	mean29-avx2 \
	lean29-generic \
	lean29-avx2 \
	mean15-generic \
	lean15-generic

PRIVEXECS = $(addprefix $(PRIV)/, $(EXECUTABLES))

PRIV = priv/bin
CUCKOO = c_src/src/cuckoo

HDRS=$(CUCKOO)/cuckoo.h $(CUCKOO)/../crypto/siphash.h

# Flags from upstream makefile
GPP_OPT ?= -O3
MSVC_OPT ?= /Ox

GPP_ARCH_FLAGS ?= -m64 -x c++
MSVC_ARCH_FLAGS ?=

# -Wno-deprecated-declarations shuts up Apple OSX clang
GPP_FLAGS ?= -Wall -Wno-format -Wno-deprecated-declarations -D_POSIX_C_SOURCE=200112L $(GPP_OPT) -DPREFETCH -I. $(CPPFLAGS) -pthread
GPP ?= g++ $(GPP_ARCH_FLAGS) -std=c++11 $(GPP_FLAGS)
MSVC_FLAGS ?= /Wall /D_POSIX_C_SOURCE=200112L $(MSVC_OPT) -DPREFETCH /I. $(CPPFLAGS)
MSVC ?= cl.exe $(MSVC_ARCH_FLAGS) $(MSVC_FLAGS)
BLAKE_2B_SRC ?= ../crypto/blake2b-ref.c
NVCC ?= nvcc -std=c++11

# end Flags from upstream

REPO = https://github.com/aeternity/cuckoo.git
COMMIT = 3ae6195a67d9dcc33b1d82fd38f9bb82f2d29ee8

.PHONY: all
all: $(EXECUTABLES)
	@: # Silence the `Nothing to be done for 'all'.` message when running `make all`.

.PHONY: clean
clean:
	@if [ -d $(PRIV) ]; then (cd $(PRIV); rm -f $(EXECUTABLES)); fi
	@if [ -d $(CUCKOO) ]; then (cd $(CUCKOO); rm -f $(EXECUTABLES)); fi

.PHONY: distclean
distclean:
	rm -rf c_src priv _build

# We want rules also for cuda29/lcuda29
EXECUTABLES += lcuda29 cuda29

.SECONDEXPANSION:
.PHONY: $(EXECUTABLES)
$(EXECUTABLES): | c_src/.git $(PRIV)
$(EXECUTABLES): git-version $(CUCKOO)/$$@ $(PRIV)/$$@

# So we need check out the right commit or cleanup if
# pointing to the wrong/old/dirty thing.
.PHONY: git-version
git-version:
ifneq ($(strip $(shell if [ -d c_src ]; then (cd c_src; git rev-parse HEAD); fi)),$(COMMIT))
	(cd c_src; git fetch; git checkout --force $(COMMIT))
else
ifneq ($(strip $(shell cd c_src && git diff-index $(COMMIT) | wc -l)),0)
	(cd c_src; git fetch; git checkout --force $(COMMIT))
endif
endif

ifeq ($(filter MINGW%,$(UNAME_S)),)
compile = cd $(CUCKOO) && $(GPP) -o $(1) $(3) $(2) $(BLAKE_2B_SRC)
else
compile = cd $(CUCKOO) && $(MSVC) /out $(1) $(3) $(2) $(BLAKE_2B_SRC)
endif

compile_nvcc = (cd $(CUCKOO); $(NVCC) -o $(1) $(3) $(2) $(BLAKE_2B_SRC))


# One rule to copy them all
$(PRIVEXECS): $(CUCKOO)/$$(@F)
	cp $(CUCKOO)/$(@F) $(PRIV)

# The args vary slightly so spell out the compilation rules
$(CUCKOO)/lean15-generic: $(HDRS) $(CUCKOO)/lean.hpp $(CUCKOO)/lean.cpp
	$(call compile,$(@F),lean.cpp,-DATOMIC -DEDGEBITS=15)

$(CUCKOO)/lean29-generic: $(HDRS) $(CUCKOO)/lean.hpp $(CUCKOO)/lean.cpp
	$(call compile,$(@F),lean.cpp,-DATOMIC -DEDGEBITS=29)

$(CUCKOO)/lean29-avx2: $(HDRS) $(CUCKOO)/lean.hpp $(CUCKOO)/lean.cpp
	$(call compile,$(@F),lean.cpp,-DATOMIC -mavx2 -DNSIPHASH=8 -DEDGEBITS=29)

$(CUCKOO)/mean15-generic: $(HDRS) $(CUCKOO)/mean.hpp $(CUCKOO)/mean.cpp
	$(call compile,$(@F),mean.cpp,-DSAVEEDGES -DXBITS=0 -DNSIPHASH=1 -DEDGEBITS=15)

$(CUCKOO)/mean29-generic: $(HDRS) $(CUCKOO)/mean.hpp $(CUCKOO)/mean.cpp
	$(call compile,$(@F),mean.cpp,-DSAVEEDGES -DNSIPHASH=1 -DEDGEBITS=29)

$(CUCKOO)/mean29-avx2: $(HDRS) $(CUCKOO)/mean.hpp $(CUCKOO)/mean.cpp
	$(call compile,$(@F),mean.cpp,-DSAVEEDGES -mavx2 -DNSIPHASH=8 -DEDGEBITS=29)

$(CUCKOO)/lcuda29: $(CUCKOO)/../crypto/siphash.cuh $(CUCKOO)/lean.cu
	$(call compile_nvcc,$(@F),lean.cu,-DEDGEBITS=29 -arch sm_35)

$(CUCKOO)/cuda29: $(CUCKOO)/../crypto/siphash.cuh $(CUCKOO)/mean.cu
	$(call compile_nvcc,$(@F),mean.cu,-DEDGEBITS=29 -arch sm_35)

# Create the private dir
$(PRIV):
	mkdir -p $@

# Clone without checking out, so that recipe interrupted after clone
# does not leave working directory distinct from the expected commit.
c_src/.git:
	git clone -n -c advice.detachedHead=false $(REPO) $(@D)
