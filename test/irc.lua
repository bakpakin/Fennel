local server_port = (os.getenv("IRC_HOST_PORT") or "irc.libera.chat 6667")
local channel = os.getenv("IRC_CHANNEL")
local url = os.getenv("JOB_URL") or "???"

local remote = io.popen("git remote get-url origin 2> /dev/null"):read('*l')
if remote == nil then
    -- no git / no git repo, this is not an upstream CI job
    return function() end
end
local is_origin = remote:find('~technomancy/fennel$') ~= nil

local branch = io.popen("git rev-parse --abbrev-ref HEAD"):read('*l')
local is_main = branch == 'main'

-- This may fail in future if libera chat once again blocks builds.sr.ht
-- from connecting; it currently works after we asked them to look into it
return function(failure_count)
    if  (0 ~= tonumber(failure_count)) and is_main and is_origin and channel then
        print("Announcing failure on", server_port, channel)

        local git_log = io.popen("git log --oneline -n 1 HEAD")
        local log = git_log:read("*a"):gsub("\n", " "):gsub("\n", " ")

        local nc = io.popen(string.format("nc %s > /dev/null", server_port), "w")

        nc:write("NICK fennel-build\n")
        nc:write("USER fennel-build 8 x : fennel-build\n")
        nc:write("JOIN " .. channel .. "\n")
        nc:write(string.format("PRIVMSG %s :Build failure! %s / %s\n",
                               channel, log, url))
        nc:write("QUIT\n")
        nc:close()
    end
    if(failure_count ~= 0) then os.exit(1) end
end
