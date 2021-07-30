;; Announce on IRC when there has been a failure in the test run.
(local server-port (or (os.getenv "IRC_HOST_PORT") "irc.libera.chat 6667"))
(local channel (os.getenv "IRC_CHANNEL"))

(local failure-count ...)

(when (and (not= 0 (tonumber failure-count)) channel)
  (print "Announcing failure on" server-port channel)
  (with-open [git (io.popen "git log --oneline -n 1 HEAD")
              nc (io.popen (string.format "nc %s > /dev/null" server-port) :w)]
    (let [log (git:read :*a)]
      (nc:write (string.format "NICK fennel-build\n"))
      (nc:write (string.format "USER fennel-build 8 x : fennel-build\n"))
      (nc:write (string.format "JOIN %s\n" channel))
      (nc:write (string.format "PRIVMSG %s :Build failure! %s" channel log))
      (nc:write "QUIT\n"))))
