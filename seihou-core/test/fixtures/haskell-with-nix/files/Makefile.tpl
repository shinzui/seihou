.PHONY: build test

build:
	cabal build all

test:
	cabal test all
