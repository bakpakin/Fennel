local server_port = (os.getenv("IRC_HOST_PORT") or "irc.libera.chat 6667")
local channel = os.getenv("IRC_CHANNEL")
local url = os.getenv("JOB_URL") or "???"

-- This may fail in future if libera chat once again blocks builds.sr.ht
-- from connecting; it currently works after we asked them to look into it
return function(failure_count)
    if ((0 ~= tonumber(failure_count)) and channel) then
        print("Announcing failure on", server_port, channel)

        local git = io.popen("git log --oneline -n 1 HEAD")
        local nc = io.popen(string.format("nc %s > /dev/null", server_port), "w")
        local log = git:read("*a"):gsub("\n", " ")

        nc:write("NICK fennel-build\n")
        nc:write("USER fennel-build 8 x : fennel-build\n")
        nc:write("JOIN " .. channel .. "\n")
        nc:write(string.format("PRIVMSG %s :Build failure! %s / %s\n",
                               channel, log, url))
        nc:write("QUIT\n")
        nc:close()
    end
end
