# No-Vary-Search Security & Privacy Questionnaire

> 01.  What information might this feature expose to Web sites or other parties, and for what purposes is that exposure necessary?

In theory, this feature can be used to give servers slightly more information about previous visits to the same origin. In general, all caches can be used by a server that detects requests vs. no-requests, to know whether the user has already visited the URL. With this feature, such servers can detect whether the user has visited variants of the same URL with different query strings.

In practice, this is not really exposing new information. Such a server can already know all sites that a given user has visited; this just lets requests to one URL (such as `https://example.com/?q=a`) also be used for checking on the status of related URLs (such as `https://example.com/?q=b`), instead of requiring two such requests.

> 02.  Do features in your specification expose the minimum amount of information necessary to enable their intended uses?

Yes.

> 03.  How do the features in your specification deal with personal information, personally-identifiable information (PII), or information derived from them?

Such information is not processed by this feature.

> 04.  How do the features in your specification deal with sensitive information?

Such information is not dealt with by this feature.

> 05.  Do the features in your specification introduce new state for an origin that persists across browsing sessions?

**No** for most caches, e.g. the prefetch and prerender caches.

**Yes** for the HTTP cache.

> 06.  Do the features in your specification expose information about the underlying platform to origins?

No.

> 07.  Does this specification allow an origin to send data to the underlying platform?

No.

> 08.  Do features in this specification enable access to device sensors?

No.

> 09.  Do features in this specification enable new script execution/loading mechanisms?

No.

> 10.  Do features in this specification allow an origin to access other devices?

No.

> 11.  Do features in this specification allow an origin some measure of control over a user agent's native UI?

No.

> 12.  What temporary identifiers do the features in this specification create or expose to the web?

None.

> 13.  How does this specification distinguish between behavior in first-party and third-party contexts?

It does not.

> 14.  How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

**No difference** for most caches, e.g. the prefetch and prerender caches.

**Potential difference** for the HTTP cache, since the HTTP cache itself behaves differently in such modes. There's nothing really special about this feature's interaction with those modes though, beyond how they already interact with the HTTP cache.

> 15.  Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

The specification is not yet complete, but see [the explainer's section](./no-vary-search.md#security-and-privacy-considerations) on that.

> 16.  Do features in your specification enable origins to downgrade default security protections?

No.

> 17.  How does your feature handle non-"fully active" documents?

It doesn't need any special handling for them. (Note: bfcache is not one of the caches this feature could ever apply to.)

> 18.  What should this questionnaire have asked?

Seems fine.
