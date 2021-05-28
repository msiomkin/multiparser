# Tarantool HTTP Multipart Rquest Parser

HTTP multipart rquests parser for LuaJIT. The project is based on [Igor Afonov's multipart parser](https://github.com/iafonov/multipart-parser-c). Works with chunks of a data - no need to buffer the whole request.

## Installation:

```shell
tarantoolctl rocks install multiparser
```

## Usage:

```Lua
local parser = require("multiparser")

-- TODO: Add usage example
```
