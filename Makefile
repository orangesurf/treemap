SWIFTC ?= swiftc
SWIFT  ?= swift
APP    := treemap
SRCS   := treemap.swift main.swift

.PHONY: all build test clean

all: build

build: $(APP)

$(APP): $(SRCS)
	$(SWIFTC) -O $(SRCS) -o $@

test:
	$(SWIFT) test

clean:
	rm -rf $(APP) .build .swiftpm
