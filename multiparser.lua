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

local function onHeaderName(self, name)
    assert(name ~= nil, "A part's header name is empty")

    self.lastHeader = name:lower()

    return 0
end

local function onHeaderValue(self, value)
    if self.lastHeader ~= nil then
        self.headers[self.lastHeader] = value
    end

    return 0
end

local function getHeaderField(header, fieldName)
    assert(header ~= nil, "'header' is nil")
    assert(fieldName ~= nil and fieldName ~= "", "'fieldName' is not specified")

    return string.match(header, fieldName .. '="?([^"^;]*)"?')
end

local finalizeFile

local function onPartData(self, data)
    if self.key ~= nil then
        assert(self.value ~= nil, "self.value is not initialized")
        self.value = self.value .. data

        return 0
    end

    if self.file == nil then
        local contentDisposition = self.headers["content-disposition"]
        if contentDisposition == nil then
            error("A part's 'Content-Disposition' header is not found")
        end

        local fileName = getHeaderField(contentDisposition, "filename")
        if fileName == nil then
            local key = getHeaderField(contentDisposition, "name")
            if key == nil then
                error("A part's name is not specified")
            end

            self.key = key

            local value = data
            self.value = value

            return 0
        end

        self.origFileName = fileName

        if self.onFileName ~= nil then
            fileName = self:onFileName(fileName)
        end

        self.fileName = fileName

        if self.file ~= nil then
            finalizeFile(self)
        end

        local fullTempFileName

        local tmpDir = self.cfg.tempDirectory
        if tmpDir ~= nil then
            assert(tmpDir ~= (self.cfg.directory or ""),
                "Temporary and main files directory coincide")
            local dirMode = self.cfg.directoryMode or 755

            local ok, err = fio.mktree(tmpDir, tonumber(dirMode, 8))
            if not ok then
                error(err)
            end

            fullTempFileName = fio.pathjoin(tmpDir, fileName)
        else
            fullTempFileName = os.tmpname()
        end

        self.fullTempFileName = fullTempFileName

        local fileMode = self.cfg.fileMode or 644
        local file, err = fio.open(fullTempFileName, { "O_CREAT", "O_WRONLY" },
            tonumber(fileMode, 8))
        if file == nil then
            error(err)
        end

        self.file = file
    end

    self.file:write(data)

    return 0
end

local function onPartEnd(self)
    if self.file ~= nil then
        self.file:close()
        self.file = nil

        local fullTempFileName = self.fullTempFileName
        assert(fullTempFileName ~= nil, "self.fullTempFileName is nil")

        local dir = self.cfg.directory or ""
        local dirMode = self.cfg.directoryMode or 755

        local ok, err = fio.mktree(dir, tonumber(dirMode, 8))
        if not ok then
            error(err)
        end

        local fileName = self.fileName
        assert(fileName ~= nil, "self.fileName is nil")

        local fullFileName = fio.pathjoin(dir, fileName)
        self.fullFileName = fullFileName

        ok, err = fio.copyfile(fullTempFileName, fullFileName)
        if not ok then
            error(err)
        end

        ok, err = fio.unlink(fullTempFileName)
        if not ok then
            error(err)
        end

        local stat
        stat, err = fio.stat(fullFileName)
        if stat == nil then
            error(err)
        end

        if self.onFileProcessed ~= nil then
            self:onFileProcessed(fileName, stat.size)
        end

        self.fileName = nil
        self.fullTempFileName = nil
        self.fullFileName = nil
    else
        assert(self.key ~= nil, "self.key is nil")
        assert(self.value ~= nil, "self.value is nil")

        self.values[self.key] = self.value

        self.key = nil
        self.value = nil
    end

    self.headers = { }

    return 0
end

local function setReadHandler(self, onRead)
    self.onRead = onRead
end

local function setFileNameHandler(self, onFileName)
    self.onFileName = onFileName
end

local freeWriteHandlers

local function setWriteHandlers(self, handlers)
    assert(self.parser == nil, "Can't change writing handlers when data processing is already in progress")

    handlers = handlers or { }

    freeWriteHandlers(self)

    if handlers.onPartBegin ~= nil then
        self.writeHandlers.on_part_data_begin = ffi.cast("multipart_notify_cb", function(_)
            return handlers.onPartBegin(self)
        end)
    end

    if handlers.onHeaderName ~= nil then
        self.writeHandlers.on_header_field = ffi.cast("multipart_data_cb", function(_, buf, length)
            local name = ffi.string(buf, length)
            return handlers.onHeaderName(self, name)
        end)
    end

    if handlers.onHeaderValue ~= nil then
        self.writeHandlers.on_header_value = ffi.cast("multipart_data_cb", function(_, buf, length)
            local value = ffi.string(buf, length)
            return handlers.onHeaderValue(self, value)
        end)
    end

    if handlers.onHeadersComplete ~= nil then
        self.writeHandlers.on_headers_complete = ffi.cast("multipart_notify_cb", function(_)
            return handlers.onHeadersComplete(self)
        end)
    end

    if handlers.onPartData ~= nil then
        self.writeHandlers.on_part_data = ffi.cast("multipart_data_cb", function(_, buf, length)
            local data = ffi.string(buf, length)
            return handlers.onPartData(self, data)
        end)
    end

    if handlers.onPartEnd ~= nil then
        self.writeHandlers.on_part_data_end = ffi.cast("multipart_notify_cb", function(_)
            return handlers.onPartEnd(self)
        end)
    end

    if handlers.onBodyEnd ~= nil then
        self.writeHandlers.on_body_end = ffi.cast("multipart_notify_cb", function(_)
            return handlers.onBodyEnd(self)
        end)
    end
end

local function setFileProcessedHandler(self, onFileProcessed)
    self.onFileProcessed = onFileProcessed
end

local function step(self, buf)
    assert(self ~= nil,
        "Use parser:read(...) instead of parser.read(...)")
    assert(buf ~= nil, "'buf' is not set")

    if self.parser == nil then
        self.parser = parserLib.multipart_parser_init(self.boundary, self.writeHandlers)
    end

    return parserLib.multipart_parser_execute(self.parser, buf, #buf)
end

local function run(self, ...)
    assert(self.onRead ~= nil,
        "Data reading callback is not specified, call parser:setReadHandler(...)")

    local bytesRead = 0

    local ok, err = pcall(function(...)
        while true do
            local buf = self:onRead(...) or ""

            local count = self:step(buf)
            bytesRead = bytesRead + count

            if buf == "" then
                break
            end
        end
    end, ...)

    self:free()

    if not ok then
        error(err)
    end

    return bytesRead
end

local function getValues(self)
    assert(self ~= nil,
        "Use parser:getValues() instead of parser.getValues()")

    return self.values
end

finalizeFile = function(self)
    if self.file ~= nil then
        self.file:close()
        self.file = nil
        if self.fullTempFileName ~= nil then
            fio.unlink(self.fullTempFileName)
        end
    end
end

freeWriteHandlers = function(self)
    if self.writeHandlers.on_part_data_begin ~= nil then
        self.writeHandlers.on_part_data_begin:free()
        self.writeHandlers.on_part_data_begin = nil
    end

    if self.writeHandlers.on_header_field ~= nil then
        self.writeHandlers.on_header_field:free()
        self.writeHandlers.on_header_field = nil
    end

    if self.writeHandlers.on_header_value ~= nil then
        self.writeHandlers.on_header_value:free()
        self.writeHandlers.on_header_value = nil
    end

    if self.writeHandlers.on_headers_complete ~= nil then
        self.writeHandlers.on_headers_complete:free()
        self.writeHandlers.on_headers_complete = nil
    end

    if self.writeHandlers.on_part_data ~= nil then
        self.writeHandlers.on_part_data:free()
        self.writeHandlers.on_part_data = nil
    end

    if self.writeHandlers.on_part_data_end ~= nil then
        self.writeHandlers.on_part_data_end:free()
        self.writeHandlers.on_part_data_end = nil
    end

    if self.writeHandlers.on_body_end ~= nil then
        self.writeHandlers.on_body_end:free()
        self.writeHandlers.on_body_end = nil
    end
end

local function free(self)
    assert(self ~= nil,
        "Use parser:free() instead of parser.free()")

    finalizeFile(self)

    freeWriteHandlers(self)

    if self.parser ~= nil then
        parserLib.multipart_parser_free(self.parser)
        self.parser = nil
    end
end

local function new(boundary, cfg)
    assert(boundary ~= nil and boundary ~= "",
        "'boundary is not set'")

    local writeHandlers = ffi.new("multipart_parser_settings")

    local obj = {
        boundary = "--" .. boundary,
        writeHandlers = writeHandlers,
        cfg = cfg or { },
        headers = { },
        values = { }
    }

    setWriteHandlers(obj, {
        onHeaderName = onHeaderName,
        onHeaderValue = onHeaderValue,
        onPartData = onPartData,
        onPartEnd = onPartEnd
    })

    return setmetatable(obj, {
        __index = {
            setReadHandler = setReadHandler,
            setFileNameHandler = setFileNameHandler,
            setWriteHandlers = setWriteHandlers,
            setFileProcessedHandler = setFileProcessedHandler,
            step = step,
            run = run,
            getValues = getValues,
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
