.PHONY: build clean

build:
	$(MAKE) solib -C multipart-parser-c
	cp multipart-parser-c/libmultipart.so .

clean:
	rm -f libmultipart.so
	$(MAKE) clean -C multipart-parser-c
