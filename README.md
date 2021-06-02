# Tarantool HTTP Multipart Request Parser

HTTP multipart requests parser for LuaJIT. The project is based on [Igor Afonov's multipart parser](https://github.com/iafonov/multipart-parser-c). Works with chunks of a data - no need to buffer the whole request.

## Installation:

```shell
tarantoolctl rocks install https://raw.githubusercontent.com/msiomkin/multiparser/main/multiparser-scm-1.rockspec
```

## Usage:

You'll need Tarantool HTTP server for this example:

```shell
tarantoolctl rocks install http
```

Now create multipart HTTP requests handler:

```lua
#!/usr/bin/env tarantool

local log = require("log")
local multiparser = require("multiparser")

local function httpPostHandler(req)
    -- Get the boundary from HTTP headers
    local contentType = req:header("content-type")
    if contentType == nil then
        error("'Content-Type' header is not specified")
    end
    
    local boundary = contentType:match("boundary=(.*)")
    if boundary == nil then
        error("Multipart boundary is not specified")
    end
    
    -- Create a parser instance
    local mParser = multiparser.new(boundary, {
        directory = "files"
    })
    
    -- Set a reading callback
    local blockSize = 4096
    mParser:setReadHandler(function()
        return req:read(blockSize)
    end)
    
    -- Do some postprocessing for each saved file
    mParser:setFileProcessedHandler(function(parser, fileName)
        log.info("Saved file: " .. fileName)
    end)
    
    -- Run the parser
    mParser:run()
    
    -- Handle key-value params if any
    local values = mParser:getValues()
    for key, value in pairs(values) do
        log.info(key .. ": " .. value)
    end
end

local server = require('http.server').new("localhost", 8000)
local router = require('http.router').new()
router:route({ path = '/upload', method = "POST" }, httpPostHandler)
server:set_router(router)
server:start()
```

Save it in srv.lua and run it:

```shell
chmod +x srv.lua
./srv.lua
```

Let's test it:

```shell
echo "Hello, World!" > example.txt
echo "Multipart parser works fine." > sample.txt
curl -v -F data="@example.txt" -F data="@sample.txt" -F author=Mike -F topic="A test greeting" "http://localhost:8000/upload"
```

You should see 'example.txt' and 'sample.txt' files in 'files' directory and
the following output in your log:

```
Saved file: .. example.txt
Saved file: .. sample.txt
author: Mike
topic: A test greeting
```
