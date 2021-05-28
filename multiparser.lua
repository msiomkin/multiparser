#!/usr/bin/env tarantool

local ffi = require("ffi")
local fio = require("fio")

ffi.cdef[[
typedef struct multipart_parser multipart_parser;
typedef struct multipart_parser_settings multipart_parser_settings;
typedef struct multipart_parser_state multipart_parser_state;

typedef int (*multipart_data_cb) (multipart_parser*, const char *at, size_t length);
typedef int (*multipart_notify_cb) (multipart_parser*);

struct multipart_parser_settings {
  multipart_data_cb on_header_field;
  multipart_data_cb on_header_value;
  multipart_data_cb on_part_data;

  multipart_notify_cb on_part_data_begin;
  multipart_notify_cb on_headers_complete;
  multipart_notify_cb on_part_data_end;
  multipart_notify_cb on_body_end;
};

multipart_parser* multipart_parser_init
    (const char *boundary, const multipart_parser_settings* settings);

void multipart_parser_free(multipart_parser* p);

size_t multipart_parser_execute(multipart_parser* p, const char *buf, size_t len);

void multipart_parser_set_data(multipart_parser* p, void* data);
void * multipart_parser_get_data(multipart_parser* p);
]]

local package = package.search("libmultipart")
local parserLib = ffi.load(package)

local function setHeaderNameHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setHeaderNameHandler(...) instead of parser.setHeaderNameHandler(...)")

    self.callbacks.on_header_field = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setHeaderValueHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setHeaderValueHandler(...) instead of parser.setHeaderValueHandler(...)")

    self.callbacks.on_header_value = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setHeadersEndHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setHeadersEndHandler(...) instead of parser.setHeadersEndHandler(...)")

    self.callbacks.on_headers_complete = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setPartDataBeginHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setPartDataBeginHandler(...) instead of parser.setPartDataBeginHandler(...)")

    self.callbacks.on_part_data_begin = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setPartDataHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setPartDataHandler(...) instead of parser.setPartDataHandler(...)")

    self.callbacks.on_part_data = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setPartDataEndHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setPartDataEndHandler(...) instead of parser.setPartDataEndHandler(...)")

    self.callbacks.on_part_data_end = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function setBodyEndHandler(self, handler, ...)
    assert(self ~= nil,
        "Use parser:setBodyEndHandler(...) instead of parser.setBodyEndHandler(...)")

    self.callbacks.on_body_end = ffi.cast("multipart_data_cb", function(_, buf, length)
        handler(self, buf, length, ...)
    end)
end

local function onHeaderName(self, buf, length)
    local name = ffi.string(buf, length)
    assert(name ~= nil, "A part's header name is empty")

    self.lastHeader = name:lower()

    return 0
end

local function onHeaderValue(self, buf, length)
    if self.lastHeader ~= nil then
        local value = ffi.string(buf, length)
        self.headers[self.lastHeader] = value
    end

    return 0
end

local function onPartDataBegin(self, buf, length, dir, mode, fileNameHandler)
    local data = ffi.string(buf, length)

    local fullFileName
    local contentDisposition = self.headers["content-disposition"]
    if contentDisposition == nil then
        error("A part's 'Content-Disposition' header is not found")
    end

    local fileName = string.match(contentDisposition, 'filename="([^"].-)"')
    if fileName == nil then
        error("A part's file name is not specified")
    end

    if fileNameHandler ~= nil then
        fileName = fileNameHandler(fileName)
    end

    fullFileName = fio.pathjoin(dir, fileName)

    if self.file ~= nil then
        self.file:close()
        self.file = nil
    end

    mode = mode or 644

    local file, err = fio.open(fullFileName, { "O_CREAT", "O_WRONLY" },
        tonumber(mode, 8))
    if file == nil then
        error(err)
    end

    file:write(data)

    return 0
end

local function onPartData(self, buf, length)
    local data = ffi.string(buf, length)

    assert(self.file ~= nil, "A part's file handle is not initialized")

    self.file:write(data)

    return 0
end

local function onPartDataEnd(self, buf, length)
    local data = ffi.string(buf, length)

    assert(self.file ~= nil, "A part's file handle is not initialized")

    self.file:write(data)

    self.headers = { }

    if self.file ~= nil then
        self.file:close()
        self.file = nil
    end

    return 0
end

local function setDefaultHandlers(self, dir, mode, fileNameHandler)
    assert(self ~= nil,
        "Use parser:setDefaultHandlers(...) instead of parser.setDefaultHandlers(...)")

    self:setHeaderNameHandler(onHeaderName)
    self:setHeaderValueHandler(onHeaderValue)
    self:setPartDataBeginHandler(onPartDataBegin, dir, mode, fileNameHandler)
    self:setPartDataHandler(onPartData)
    self:setPartDataEndHandler(onPartDataEnd)
end

local function read(self, buf)
    assert(self ~= nil,
        "Use parser:read(...) instead of parser.read(...)")
    assert(buf ~= nil, "'buf' is not set")

    parserLib.multipart_parser_execute(self.parser, buf, #buf)
end

local function getVars(self)
    assert(self ~= nil,
        "Use parser:getVars() instead of parser.getVars()")

    return self.vars
end

local function free(self)
    assert(self ~= nil,
        "Use parser:free() instead of parser.free()")

    if self.file ~= nil then
        self.file:close()
    end

    if self.callbacks.on_header_field ~= nil then
        self.callbacks.on_header_field:free()
    end

    if self.callbacks.on_header_value ~= nil then
        self.callbacks.on_header_value:free()
    end

    if self.callbacks.on_headers_complete ~= nil then
        self.callbacks.on_headers_complete:free()
    end

    if self.callbacks.on_part_data_begin ~= nil then
        self.callbacks.on_part_data_begin:free()
    end

    if self.callbacks.on_part_data ~= nil then
        self.callbacks.on_part_data:free()
    end

    if self.callbacks.on_part_data_end ~= nil then
        self.callbacks.on_part_data_end:free()
    end

    if self.callbacks.on_body_end ~= nil then
        self.callbacks.on_body_end:free()
    end

    parserLib.multipart_parser_free(self.parser)
end

local function new(boundary)
    assert(boundary ~= nil and boundary ~= "",
        "'boundary is not set'")

    local callbacks = ffi.new("multipart_parser_settings")
    local parser = parserLib.multipart_parser_init(boundary, callbacks)

    local obj = {
        boundary = boundary,
        callbacks = callbacks,
        parser = parser,
        headers = { },
        vars = { }
    }

    return setmetatable(obj, {
        __index = {
            setHeaderNameHandler = setHeaderNameHandler,
            setHeaderValueHandler = setHeaderValueHandler,
            setHeadersEndHandler = setHeadersEndHandler,
            setPartDataBeginHandler = setPartDataBeginHandler,
            setPartDataHandler = setPartDataHandler,
            setPartDataEndHandler = setPartDataEndHandler,
            setBodyEndHandler = setBodyEndHandler,
            setDefaultHandlers = setDefaultHandlers,
            read = read,
            getVars = getVars,
            free = free
        },
        __gc = function(self)
            free(self)
        end
    })
end

return {
    new = new
}
