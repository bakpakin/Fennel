# Security

Please report potential security issues with the Fennel compiler or
web site to [phil@hagelb.org][1] and [jaawerth@gmail.com][2].

Sensitive reports may be encrypted with the PGP key listed below.

Please do not submit LLM-generated security reports; this will get you banned.

## Signatures

From version 0.10.0 onward, Fennel releases and tags have been signed
with the PGP key [8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6][3].
Before that the key [20242BACBBE95ADA22D0AFD7808A33D379C806C3][4] was used.

To verify:

    $ curl https://technomancy.us/8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6.txt | gpg --import -
    $ gpg --verify fennel-1.2.0.asc

From 1.0 onwards, releases are also signed with `.sig` files using SSH keys:

    $ curl -o allowed https://fennel-lang.org/downloads/allowed_signers
    $ ssh-keygen -Y verify -f allowed -I phil@hagelb.org -n file -s fennel-1.2.0.sig < fennel-1.2.0

You can compare the key in the [allowed][5] file with the keys
published at [technomancy.us][6], [SourceHut][7], or [GitHub][8].

## Historical Issues

In versions from 1.0.0 to 1.3.1, it was possible for code running in
the compiler sandbox to call un-sandboxed functions from applications
or Fennel libraries when running with metadata enabled. This could
result in RCE when evaluating untrusted code in a way that relied on
the sandbox for services running with metadata enabled.

In addition, even when metadata was disabled, it was still possible
for sandboxed code to trigger loading of a module already on the load
path. In most cases if an attacker can get a file on the load-path
then they've already won, but in the context of tools that run static
analysis on untrusted code, this could result in a vulnerability.

Versions prior to 1.0.0 did not sandbox macros.

[1]: mailto:phil@hagelb.org
[2]: mailto:jaawerth@gmail.com
[3]: https://technomancy.us/8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6.txt
[4]: https://technomancy.us/20242BACBBE95ADA22D0AFD7808A33D379C806C3.txt
[5]: https://fennel-lang.org/downloads/allowed_signers
[6]: https://technomancy.us/keys
[7]: https://meta.sr.ht/~technomancy.keys
[8]: https://github.com/technomancy.keys
