package = "multiparser"

version = "scm-1"

source = {
    url = "git://github.com/msiomkin/multiparser.git",
    branch = "master"
}

description = {
    summary  = "HTTP multipart rquests parser for LuaJIT",
    detailed = [[
    HTTP multipart rquests parser for LuaJIT. The project is based on [Igor Afonov's
    multipart parser](https://github.com/iafonov/multipart-parser-c). Works with chunks
    of a data - no need to buffer the whole request.
    ]],
    homepage = "https://github.com/msiomkin/multiparser",
    maintainer = "Mike Siomkin <msiomkin@mail.ru>",
    license = "MIT"
}

dependencies = {
    "lua >= 5.1"
}

build = {
    type = "make",
    install_variables = {
        INST_PREFIX = "$(PREFIX)",
        INST_BINDIR = "$(BINDIR)",
        INST_LIBDIR = "$(LIBDIR)",
        INST_LUADIR = "$(LUADIR)",
        INST_CONFDIR = "$(CONFDIR)"
    }
}
