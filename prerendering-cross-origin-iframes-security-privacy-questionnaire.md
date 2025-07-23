# Security and Privacy Questionnaire: Prerendering cross-origin iframes

> 1. What information does this feature expose, and for what purposes?

None.

> 2. Do features in your specification expose the minimum amount of information necessary to implement the intended functionality?

Yes.

> 3. Do the features in your specification expose personal information, personally-identifiable information (PII), or information derived from either?

No.

> 4. How do the features in your specification deal with sensitive information?

They do not.

> 5. Does data exposed by your specification carry related but distinct information that may not be obvious to users?

No.

> 6. Do the features in your specification introduce state that persists across browsing sessions?

No.

> 7. Do the features in your specification expose information about the underlying platform to origins?

No.

8. Does this specification allow an origin to send data to the underlying platform?

No.

> 9. Do features in this specification enable access to device sensors?

No.

> 10. Do features in this specification enable new script execution/loading mechanisms?

Not really; it allows existing mechanisms (i.e., iframes which contain script) to work in contexts where they were previously delayed from executing.

> 11. Do features in this specification allow an origin to access other devices?

No.

> 12. Do features in this specification allow an origin some measure of control over a user agent's native UI?

No.

> 13. What temporary identifiers do the features in this specification create or expose to the web?

None.

> 14. How does this specification distinguish between behavior in first-party and third-party contexts?

This feature can only be used by top-level pages, not by embedded third parties.

> 15. How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

The same as in normal mode.

> 16. Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

Yes, and the [explainer](./prerendering-cross-origin-iframes.md#privacy-considerations) has specific discussion.

> 17. Do features in your specification enable origins to downgrade default security protections?

No. (The delayed loading of cross-origin iframes while prerendering is not a security protection.)

> 18. What happens when a document that uses your feature is kept alive in BFCache (instead of getting destroyed) after navigation, and potentially gets reused on future navigations back to the document?

This isn't applicable, as prerendered pages cannot be kept in BFCache.

> 19. What happens when a document that uses your feature gets disconnected?

This isn't applicable, as prerendered pages cannot be included in iframes that get disconnected.

> 20. Does your spec define when and how new kinds of errors should be raised?

No new errors are raised.

> 21. Does your feature allow sites to learn about the user's use of assistive technology?

No.

> 22. What should this questionnaire have asked?

Probably something about "how does this all interact with storage partitioning".
