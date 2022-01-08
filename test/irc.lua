local server_port = (os.getenv("IRC_HOST_PORT") or "irc.libera.chat 6667")
local channel = os.getenv("IRC_CHANNEL")
local url = os.getenv("JOB_URL") or "???"

local failure_count = ...

if ((0 ~= tonumber(failure_count)) and channel) then
  print("Announcing failure on", server_port, channel)

  local git = io.popen("git log --oneline -n 1 HEAD")
  local nc = io.popen(string.format("nc %s > /dev/null", server_port), "w")
  local log = git:read("*a")

  nc:write(string.format("NICK fennel-build\n"))
  nc:write(string.format("USER fennel-build 8 x : fennel-build\n"))
  nc:write(string.format("JOIN %s\n", channel))
  nc:write(string.format("PRIVMSG %s :Build failure! %s | %s",
                         channel, log, url))
  nc:write("QUIT\n")
end
