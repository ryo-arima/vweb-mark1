.PHONY: build run test

build:
	v -prod -o .bin/service-b-back ./cmd/server

run:
	v run ./cmd/server

test:
	v test test/unit
	v test pkg/server/share
	v test pkg/server/usecase
	v test pkg/server/repository
