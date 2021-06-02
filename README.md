# Tarantool HTTP Multipart Request Parser

HTTP multipart requests parser for LuaJIT. The project is based on [Igor Afonov's multipart parser](https://github.com/iafonov/multipart-parser-c). Works with chunks of a data - no need to buffer the whole request.

## Installation

```shell
tarantoolctl rocks install https://raw.githubusercontent.com/msiomkin/multiparser/main/multiparser-scm-1.rockspec
```

## Usage

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
    -- (The following options are available:
    -- tempDirectory - temp directory, "/tmp" by default
    -- directory - directory for saving files, the app's directory by default
    -- directoryMode - access rights for saved files directory, 755 by default
    -- fileMode = access rights for saved files, 644 by default)
    local mParser = multiparser.new(boundary, {
        directory = "files"
    })
    
    -- Set a reading callback
    local blockSize = 4096
    mParser:setReadHandler(function()
        return req:read(blockSize)
    end)
    
    -- You may change the original file name here if you want:
    mParser:setFileNameHandler(function(parser, fileName)
        return "my_" .. fileName
    end)
    
    -- Do some postprocessing for each saved file
    mParser:setFileProcessedHandler(function(parser, fileName, size)
        log.info("Saved file: " .. fileName .. ", " ..
            tostring(size) .. " bytes")
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

You should see 'my_example.txt' and 'my_sample.txt' files in 'files' directory and
the following output in your log:

```
Saved file: my_example.txt, 14 bytes
Saved file: my_sample.txt, 29 bytes
author: Mike
topic: A test greeting
```

## Advanced Usage

You may also override the default data writing handles if you need some
non-trivial data processing (in this case no files will be created
automatically and 'getValues' method won't work):

```lua
local multiparser = require("multiparser")

-- ...

local mParser = multiparser.new(
    -- ...
)

-- ...

mParser:setWritingHandlers({
    onPartBegin = function(parser)
        -- ...
    end,
    
    onHeaderName = function(parser, name)
        -- ...
    end,
    
    onHeaderValue = function(parser, value)
        -- ...
    end,
    
    onHeadersComplete = function(parser)
        -- ...
    end,
    
    onPartData = function(parser, data)
        -- ...
    end,
    
    onPartEnd = function(parser)
        -- ...
    end,
    
    onBodyEnd = function(parser)
        -- ...
    end
})

-- ...

mParser:run()

-- ...
```
