.PHONY: build clean

build:
	$(MAKE) solib -C multipart-parser-c

clean:
	$(MAKE) clean -C multipart-parser-c

install:
	cp multipart-parser-c/libmultipart.so $(INST_LIBDIR)
	cp multiparser.lua $(INST_LUADIR)
