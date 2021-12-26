# Security

Please report potential security issues with the Fennel compiler or
web site to [phil@hagelb.org][1] and [jaawerth@gmail.com][2].

Sensitive reports may be encrypted with the PGP key listed below.

From version 0.10.0 onward, Fennel releases and tags have been signed
with the PGP key [8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6][3].
Before that the key [20242BACBBE95ADA22D0AFD7808A33D379C806C3][4] was used.

To verify:

    $ curl https://technomancy.us/8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6.txt | gpg --import -
    $ gpg --verify 

From 1.0 onwards, releases are also signed using SSH keys:

    $ curl -O allowed https://fennel-lang.org/downloads/allowed_signers
    $ ssh-keygen -Y verify -f allowed -I phil@hagelb.org -n file -s fennel-1.0.0.sig < fennel-1.0.0

You can check the key in the [allowed][5] file at [technomancy.us][6],
[on SourceHut][7], or [on GitHub][8].

[1]: mailto:phil@hagelb.org
[2]: mailto:jaawerth@gmail.com
[3]: https://technomancy.us/8F2C85FFC1EBC016A3B683DE8BD38C28CCFD2DA6.txt
[4]: https://technomancy.us/20242BACBBE95ADA22D0AFD7808A33D379C806C3.txt
[5]: https://fennel-lang.org/downloads/allowed_signers
[6]: https://technomancy.us/keys
[7]: https://meta.sr.ht/~technomancy.keys
[8]: https://github.com/technomancy.keys
