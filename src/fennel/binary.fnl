;; This module compiles Fennel modules into standalone executable programs.
;; It can be considered "downstream" of the rest of the compiler and is somewhat
;; independent.

;; based on https://github.com/ers35/luastatic/
(local fennel (require :fennel))

(fn shellout [command]
  (let [f (io.popen command)
        stdout (f:read :*all)]
    (and (f:close) stdout)))

(fn execute [cmd]
  (match (os.execute cmd)
    0 true
    true true))

(fn string->c-hex-literal [characters]
  (let [hex []]
    (each [character (characters:gmatch ".")]
      (table.insert hex (: "0x%02x" :format (string.byte character))))
    (table.concat hex ", ")))

(local c-shim
       "#ifdef __cplusplus
extern \"C\" {
#endif
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef __cplusplus
}
#endif
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if LUA_VERSION_NUM == 501
  #define LUA_OK 0
#endif

/* Copied from lua.c */

static lua_State *globalL = NULL;

static void lstop (lua_State *L, lua_Debug *ar) {
  (void)ar;  /* unused arg. */
  lua_sethook(L, NULL, 0, 0);  /* reset hook */
  luaL_error(L, \"interrupted!\");
}

static void laction (int i) {
  signal(i, SIG_DFL); /* if another SIGINT happens, terminate process */
  lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

static void createargtable (lua_State *L, char **argv, int argc, int script) {
  int i, narg;
  if (script == argc) script = 0;  /* no script name? */
  narg = argc - (script + 1);  /* number of positive indices */
  lua_createtable(L, narg, script + 1);
  for (i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - script);
  }
  lua_setglobal(L, \"arg\");
}

static int msghandler (lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg == NULL) {  /* is error object not a string? */
    if (luaL_callmeta(L, 1, \"__tostring\") &&  /* does it have a metamethod */
        lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
      return 1;  /* that is the message */
    else
      msg = lua_pushfstring(L, \"(error object is a %%s value)\",
                            luaL_typename(L, 1));
  }
  /* Call debug.traceback() instead of luaL_traceback() for Lua 5.1 compat. */
  lua_getglobal(L, \"debug\");
  lua_getfield(L, -1, \"traceback\");
  /* debug */
  lua_remove(L, -2);
  lua_pushstring(L, msg);
  /* original msg */
  lua_remove(L, -3);
  lua_pushinteger(L, 2);  /* skip this function and traceback */
  lua_call(L, 2, 1); /* call debug.traceback */
  return 1;  /* return the traceback */
}

static int docall (lua_State *L, int narg, int nres) {
  int status;
  int base = lua_gettop(L) - narg;  /* function index */
  lua_pushcfunction(L, msghandler);  /* push message handler */
  lua_insert(L, base);  /* put it under function and args */
  globalL = L;  /* to be available to 'laction' */
  signal(SIGINT, laction);  /* set C-signal handler */
  status = lua_pcall(L, narg, nres, base);
  signal(SIGINT, SIG_DFL); /* reset C-signal handler */
  lua_remove(L, base);  /* remove message handler from the stack */
  return status;
}

int main(int argc, char *argv[]) {
 lua_State *L = luaL_newstate();
 luaL_openlibs(L);
 createargtable(L, argv, argc, 0);

 static const unsigned char lua_loader_program[] = {
%s
};
  if(luaL_loadbuffer(L, (const char*)lua_loader_program,
                     sizeof(lua_loader_program), \"%s\") != LUA_OK) {
    fprintf(stderr, \"luaL_loadbuffer: %%s\\n\", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }

  /* lua_bundle */
  lua_newtable(L);
  static const unsigned char lua_require_1[] = {
  %s
  };
  lua_pushlstring(L, (const char*)lua_require_1, sizeof(lua_require_1));
  lua_setfield(L, -2, \"%s\");

%s

  if (docall(L, 1, LUA_MULTRET)) {
    const char *errmsg = lua_tostring(L, 1);
    if (errmsg) {
      fprintf(stderr, \"%%s\\n\", errmsg);
    }
    lua_close(L);
    return 1;
  }
  lua_close(L);
  return 0;
}")

(macro loader []
  `(do (local bundle# ...)
       (fn loader# [name#]
         (match (or (. bundle# name#) (. bundle# (.. name# ".init")))
           (mod# ? (= :function (type mod#))) mod#
           (mod# ? (= :string (type mod#))) (assert
                                             (if (= _VERSION "Lua 5.1")
                                                 (loadstring mod# name#)
                                                 (load mod# name#)))
           nil (values nil (: "\n\tmodule '%%s' not found in fennel bundle"
                              :format name#))))
       (table.insert (or package.loaders package.searchers) 2 loader#)
       ((assert (loader# "%s")) ((or unpack table.unpack) arg))))

(fn compile-fennel [filename options]
  (let [f (if (= filename "-")
              io.stdin
              (assert (io.open filename :rb)))
        lua-code (fennel.compile-string (f:read :*a) options)]
    (f:close)
    lua-code))

(fn native-loader [native]
  (let [nm (or (os.getenv "NM") "nm")
        out ["  /* native libraries */"]]
    (each [_ path (ipairs native)]
      (each [open (: (shellout (.. nm " " path))
                     :gmatch "[^dDt] _?luaopen_([%a%p%d]+)")]
        (table.insert out (: "  int luaopen_%s(lua_State *L);" :format open))
        (table.insert out (: "  lua_pushcfunction(L, luaopen_%s);" :format open))
        (table.insert out (: "  lua_setfield(L, -2, \"%s\");\n"
                             ;; changing initial underscore breaks luaossl
                             :format (.. (open:sub 1 1)
                                         (-> (open:sub 2)
                                             (: :gsub "_" ".")))))))
    (table.concat out "\n")))

(fn fennel->c [filename native options]
  (let [basename (filename:gsub "(.*[\\/])(.*)" "%2")
        basename-noextension (or (basename:match "(.+)%.") basename)
        dotpath (-> filename
                    (: :gsub "^%.%/" "")
                    (: :gsub "[\\/]" "."))
        dotpath-noextension (or (dotpath:match "(.+)%.") dotpath)
        fennel-loader (: (macrodebug (loader) :do) :format dotpath-noextension)
        lua-loader (fennel.compile-string fennel-loader)]
    (c-shim:format (string->c-hex-literal lua-loader)
                   basename-noextension
                   (string->c-hex-literal (compile-fennel filename options))
                   dotpath-noextension
                   (native-loader native))))

(fn write-c [filename native options]
  (let [out-filename (.. filename "_binary.c")
        f (assert (io.open out-filename "w+"))]
    (f:write (fennel->c filename native options))
    (f:close)
    out-filename))

(fn compile-binary [lua-c-path executable-name static-lua lua-include-dir native]
  (let [cc (or (os.getenv "CC") "cc")
        ;; http://lua-users.org/lists/lua-l/2009-05/msg00147.html
        (rdynamic bin-extension ldl?) (if (: (shellout (.. cc " -dumpmachine"))
                                             :match "mingw")
                                          (values "" ".exe" false)
                                          (values "-rdynamic" "" true))
        compile-command [cc "-Os" ; optimize for size
                         lua-c-path
                         (table.concat native " ")
                         static-lua
                         rdynamic
                         "-lm"
                         (if ldl? "-ldl" "")
                         "-o" (.. executable-name bin-extension)
                         "-I" lua-include-dir
                         (os.getenv "CC_OPTS")]]
    (when (os.getenv "FENNEL_DEBUG")
      (print "Compiling with" (table.concat compile-command " ")))
    (when (not (execute (table.concat compile-command " ")))
      (print :failed: (table.concat compile-command " "))
      (os.exit 1))
    (when (not (os.getenv "FENNEL_DEBUG"))
      (os.remove lua-c-path))
    (os.exit 0)))

(fn native-path? [path]
  (match (path:match "%.(%a+)$")
    :a path :o path :so path :dylib path
    _ false))

(fn extract-native-args [args]
  ;; all native libraries go in libraries; those with lua code go in modules too
  (let [native {:modules [] :libraries []}]
    (for [i (# args) 1 -1]
      (when (= "--native-module" (. args i))
        (let [path (assert (native-path? (table.remove args (+ i 1))))]
          (table.insert native.modules 1 path)
          (table.insert native.libraries 1 path)
          (table.remove args i)))
      (when (= "--native-library" (. args i))
        (table.insert native.libraries 1
                      (assert (native-path? (table.remove args (+ i 1)))))
        (table.remove args i)))
    (when (< 0 (# args))
      (print (table.concat args " "))
      (error (.. "Unknown args: " (table.concat args " "))))
    native))

(fn compile [filename executable-name static-lua lua-include-dir options args]
  (let [{: modules : libraries} (extract-native-args args)]
    (compile-binary (write-c filename modules options) executable-name
                    static-lua lua-include-dir libraries)))

(local help (: "
Usage: %s --compile-binary FILE OUT STATIC_LUA_LIB LUA_INCLUDE_DIR

Compile a binary from your Fennel program.

Requires a C compiler, a copy of liblua, and Lua's dev headers. Implies
the --require-as-include option.

  FILE: the Fennel source being compiled.
  OUT: the name of the executable to generate
  STATIC_LUA_LIB: the path to the Lua library to use in the executable
  LUA_INCLUDE_DIR: the path to the directory of Lua C header files

For example, on a Debian system, to compile a file called program.fnl using
Lua 5.3, you would use this:

    $ %s --compile-binary program.fnl program \\
        /usr/lib/x86_64-linux-gnu/liblua5.3.a /usr/include/lua5.3

The program will be compiled to Lua, then compiled to C, then compiled to
machine code. You can set the CC environment variable to change the compiler
used (default: cc) or set CC_OPTS to pass in compiler options. For example
set CC_OPTS=-static to generate a binary with static linking.

To include C libraries that contain Lua modules, add --native-module path/to.so,
and to include C libraries without modules, use --native-library path/to.so.
These options are unstable, barely tested, and even more likely to break.

This method is currently limited to programs do not transitively require Lua
modules. Requiring a Lua module directly will work, but requiring a Lua module
which requires another will fail." :format (. arg 0) (. arg 0)))

{: compile : help}
