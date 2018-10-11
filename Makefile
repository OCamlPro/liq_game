all: build

build: _obuild
	ocp-build build

install: _obuild
	ocp-build install

_obuild: Makefile
	ocp-build init

clean-sources:
	rm -f src/*~

clean: _obuild clean-sources
	ocp-build clean

distclean: clean
	rm -rf _obuild
