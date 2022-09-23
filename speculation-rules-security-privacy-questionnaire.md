# Security & Privacy Questionnaire (Speculation Rules)

Covers the [speculation rules explainer](triggers.md). Based on the [W3C TAG Self-Review Questionnaire: Security and Privacy](https://w3ctag.github.io/security-questionnaire/).

### What information might this feature expose to Web sites or other parties, and for what purposes is that exposure necessary?

At its core the feature does not expose new information to web sites or other parties. However, the user agent may expose information as a consequence of use of this feature.

The feature allows the user agent to use its discretion about which outgoing hypertext references should be prefetched. While we anticipate that user agents will take action to [mitigate user tracking risks](prerendering-cross-origin.md#privacy-based-restrictions) for cross-origin prefetches, including by denying access to cookies and storage, it remains true that the origin server that serves a prefetch may learn information such as:
* the request URL
* the referrer origin from which the prefetch was initiated
* any information remaining in the request headers which may identify the user agent
* the client IP address, if it is not anonymized

This is necessary in order to issue an HTTP request to fetch the resource(s); this information is also sent with a scripted `fetch()` or similar.

To the extent that the user agent uses heuristics to determine whether prefetching, prerendering, or similar actions are worthwhile, whether a prefetch occurs may be observable by the origin server and may reveal some information about the inputs to those heuristics, such as models of predicted user activity (i.e., is the user likely to select this link) and of the expense associated with the speculated activity (e.g., device class, battery level, network connection quality).

This is necessary in order to ensure that useful speculated activity can occur to reduce the latency of navigation, while simultaneously limiting adverse effects to the user (e.g. due to limited battery life or metered network bandwidth).

User agents should balance minimization of this information against the benefits of selecting the speculation most likely to be beneficial to the user.

To the extent that the user agent satisfies requirements for client IP anonymization by using a [proxy server](https://github.com/buettner/private-prefetch-proxy), doing so may reveal some information to its operator, such as the destination origin and encrypted network traffic. Feedback on the use of a private prefetch proxy is welcome on a [separate repository](https://github.com/buettner/private-prefetch-proxy/issues).

Much of this exposure is in theory already happening with existing resource hints such as `<link rel=prefetch>`.

### Do features in your specification expose the minimum amount of information necessary to enable their intended uses?

Largely, yes, though the specification leaves some freedom to user agents to determine whether to perform a prefetch, prerender or similar, and their implementation choices may determine whether more than the minimum amount of information is exposed through side channels.

### How do the features in your specification deal with personal information, personally-identifiable information (PII), or information derived from them?

This is substantially similar to the answer to the first question.

The prefetches/prerenders themselves may include PII if a site includes them in the requested URL (as with any outgoing fetch or navigation).

The fact that a prefetch or prerender occurs is visible to its origin server. Accordingly, user agents should avoid basing this decision on personal information not already known to the site. For example, if a user agent prefetched a link based on a profile of the user's interests from their browsing activity across the web, the fact that a prefetch was executed may reveal information about those interests that would not have otherwise been exposed.

To the extent that the user agent modifies the path taken by network traffic in order to accommodate a request to anonymize the client IP address, encrypted traffic that may be derived from PII may be visible to parties along the revised network path, including the proxy operator. To mitigate this, traffic should be encrypted with TLS and [not include cookies or other identifiers](fetch.md#fetching-with-no-credentials).

### How do the features in your specification deal with sensitive information?

This is similar to the previous response. An origin could use prefetches to communicate sensitive information in the URL of a prefetch, as it can today using hyperlinks, fetch, or subresources, but the feature does not itself operate on sensitive information.

### Do the features in your specification introduce new state for an origin that persists across browsing sessions?

No.

A user agent might use persistent state of some kind (for example, whether link destinations have been previously visited from this origin) to determine whether prefetching is likely to be useful, but this is not mandated by the specification.

### Do the features in your specification expose information about the underlying platform to origins?

No, except to the extent that this information is used in heuristics that determine whether speculated actions are executed.

### Does this specification allow an origin to send data to the underlying platform?

No.

### Does this specification allow an origin access to sensors on a user’s device?

No.

### What data do the features in this specification expose to an origin? Please also document what data is identical to data exposed by other features, in the same or different contexts.

The origin using this feature provides information to the user agent. That origin or other origins may gain information as a consequence of the prefetch or prerender subsequently executed, as discussed above.

This is broadly similar to the way that an origin can intentionally expose information to other servers by requesting a subresource, issuing a scripted fetch, or using an existing [resource hint](https://w3c.github.io/resource-hints/).

Of note is that the destination server may learn that the speculation action was taken by the user agent, which may imply that the user agent believes this will be productive and thus, by implication, some information about the resource constraints on the device or predicted user behavior on the current document.

### Does this specification enable new script execution/loading mechanisms?

It provides a new way of initiating behavior previously available through Resource Hints. These behaviors are presently poorly specified. We are working to more formally explain them and address their security and privacy considerations (including in anticipation of the removal of third-party cookies from the web), though that is not strictly part of the speculation rules proposal.

### Does this specification allow an origin to access other devices?

No.

### Do features in this specification allow an origin some measure of control over a user agent’s native UI?

No.

### What temporary identifiers do the features in this specification create or expose to the web?

None known.

### How does this specification distinguish between behavior in first-party and third-party contexts?

It doesn't directly, though the behavior of initiated actions may vary. For instance, prefetches initiated in a third-party context would need to respect any storage and cache partitioning the browser does, and prerendering is not possible in a subframe (thus cannot occur in a third-party context).

### How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

The specification does not yet address this in detail, but it should behave normally except that no information outside the private browsing session should be used, nor should information from the private browsing session persist in a way that affects speculation activity outside the session.

Browsers could choose to behave more conservatively, but doing so may make it possible to detect private browsing mode.

### Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

Not as yet, though we recognize that it cannot be considered complete without one.

We do discuss security and privacy considerations thoroughly in the relevant explainers, and will be porting that into the overall "prerendering revamped" specification as that specification gets more concrete.

### Do features in your specification enable origins to downgrade default security protections?

No.
