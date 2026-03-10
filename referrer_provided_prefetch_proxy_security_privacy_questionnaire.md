# Questions to Consider

## 2.1 What information does this feature expose, and for what purposes?

This feature exposes information about speculative navigations requested by a site to a prefetch proxy server that is operated by the same site. The following information is newly exposed to the first-party proxy operator:

* Which speculation rule prefetches are executed  
* Speculation rule timing: when are rules executed

This feature does not expose information to third parties: prefetch proxies are required to be same-site to the referrer document. 

## 2.2 Do features in your specification expose the minimum amount of information necessary to implement the intended functionality?

Yes: a proxy server is required to implement the IP anonymization functionality that is specified in the new speculation rules requirements.

## 2.3 Do the features in your specification expose personal information, personally-identifiable information (PII), or information derived from either?

No.

## 2.4 How do the features in your specification deal with sensitive information?

This feature requires a prefetch proxy to be same-site to the referring document so that no information is exposed to any party that the party could not already access. All other restrictions of cross-site prefetching remain in effect.

## 2.5 Does data exposed by your specification carry related but distinct information that may not be obvious to users?

No. Prefetch proxies are required to not expose user metadata or fingerprinting vectors to origins, including but not limited to client cookies.

## 2.6 Do the features in your specification introduce state that persists across browsing sessions?

No. Prefetched documents will be discarded once the user navigates away from the primary page or closes the tab.

## 2.7 Do the features in your specification expose information about the underlying platform to origins?

No.

## 2.8 Does this specification allow an origin to send data to the underlying platform?

No.

## 2.9 Do features in this specification enable access to device sensors?

No.

## 2.10 Do features in this specification enable new script execution/loading mechanisms?

No. It changes how existing speculationrules scripts are parsed by introducing new speculation rules requirements, but does not introduce new execution or loading mechanisms.

## 2.11 Do features in this specification allow an origin to access other devices?

No.

## 2.12 Do features in this specification allow an origin some measure of control over a user agent’s native UI?

No.

## 2.13 What temporary identifiers do the features in this specification create or expose to the web?

Use of a prefetch proxy should not be considered a temporary identifier because proxies aggregate multiple users’ traffic through their egress IP ranges and further anonymize prefetch requests.

## 2.14 How does this specification distinguish between behavior in first-party and third-party contexts?

This feature aims to restrict sites from sending data from first-party to third-party contexts by introducing a same-site requirement for prefetch proxies. The provided prefetch proxy must be same-site to the referrer document.

## 2.15 How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

No change in behavior between standard and private/incognito modes.

## 2.16 Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

Yes.

## 2.17 Do features in your specification enable origins to downgrade default security protections?

No, it inherits all the security and privacy protections of standard prefetching.
