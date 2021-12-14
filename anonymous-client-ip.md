# Anonymous Client IP

## Why anonymize the client IP when prefetching for navigation?

The [role of the client IP address in Internet privacy][ietf-ip-privacy] has been discussed elsewhere, and many software vendors and service providers have started offering features which obscure it, e.g., using a proxy or virtual private network.

Outgoing prefetch traffic may imply information about the content the user is currently viewing before they have clicked a link. Accordingly, some sites (e.g., search engines, email providers, and social media networks) may be happy to enhance the performance of outbound navigations to other sites only if client IP anonymity is possible. For navigations from such sites, users with IP privacy may actually experience better performance than possible without it.

## Is IP-anonymized prefetching feasible for browsers?

Yes. Many major browser vendors already offer an HTTP proxy or VPN service to protect IP privacy, such as Google Chrome's [private prefetch proxy][chrome-ppp], Safari's [iCloud Private Relay][safari-ipr], [Mozilla VPN][mozilla-vpn] and [Opera VPN][opera-vpn]. This technology can be leveraged to enable private prefetch for eligible users.

## How can browsers know which prefetches require anonymous client IP?

The Speculation Rules syntax allows authors to [expressly mark](triggers.md#extension-requirements) that particular cross-origin prefetches should only occur when the browser can anonymize the client IP. Browsers must not execute such rules otherwise.

[ietf-ip-privacy]: https://datatracker.ietf.org/doc/draft-ip-address-privacy-considerations/
[chrome-ppp]: https://blog.chromium.org/2020/12/continuing-our-journey-to-bring-instant.html#:~:text=to%20the%20user.-,Private%20prefetch%20proxy,between%20Chrome%20and%20that%20website.
[safari-ipr]: https://support.apple.com/en-ca/HT212614
[mozilla-vpn]: https://www.mozilla.org/products/vpn/
[opera-vpn]: https://www.opera.com/features/free-vpn