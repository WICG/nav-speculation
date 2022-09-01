# Security & Privacy Questionnaire (same-site prerendering)

Covers the specific case of [same-site prerendering](./prerendering-same-site.md) triggered by [speculation rules](./triggers.md). Based on the [W3C TAG Self-Review Questionnaire: Security and Privacy](https://w3ctag.github.io/security-questionnaire/).

For general [speculation rules](triggers.md) including cross-origin cases, see that [questionnaire](speculation-rules-security-privacy-questionnaire.md). Some answers below are inspired by that document.

### What information might this feature expose to Web sites or other parties, and for what purposes is that exposure necessary?

At its core, this feature does not expose any additional information because it is restricted to same-site triggers. The page cannot do anything it cannot already do with an iframe.

However, the user agent chooses whether to act upon the page's hint to prerender a URL at its own discretion. If the user agent uses heuristics such as the user's engagement with the origin to make that decision, the origin can potentially glean information based on whether the user agent acts upon the hint or not.

### Do features in your specification expose the minimum amount of information necessary to enable their intended uses?

This is similar to the previous response. The specification leaves some freedom to user agents to determine whether to perform a prerender, and their implementation choices may determine whether more than the minimum amount of information is exposed through side channels.

### How do the features in your specification deal with personal information, personally-identifiable information (PII), or information derived from them?

This is similar to the previous responses. User agents should avoid basing heuristics on personal information not already known to the site. For example, if a user agent prerenders a link based on a profile of the user's interests from their browsing activity across the web, the fact that a prerender was executed may reveal information about those interests that would not have otherwise been exposed.

### How do the features in your specification deal with sensitive information?

This is similar to the previous responses. There is no additional information that can be communicated from the site to itself that it cannot already do via an iframe. But the user agent's heuristics deciding whether to honor a prerender hint can potentially leak information.

### Do the features in your specification introduce new state for an origin that persists across browsing sessions?

No.

### Do the features in your specification expose information about the underlying platform to origins?

No, except to the extent that this information is used in heuristics that determine whether speculated actions are executed.

### Does this specification allow an origin to send data to the underlying platform?

No.

### Does this specification allow an origin access to sensors on a user’s device?

No.

### What data do the features in this specification expose to an origin? Please also document what data is identical to data exposed by other features, in the same or different contexts.

The origin can tell if a page is being prerendered using `document.prerendering` and can tell when that page is activated by using `prerenderingchange`. See the [questionnaire](prerendering-state-privacy-questionnaire.md) for [Prerendering State](prerendering-state.md) for those particular data.

The origin can tell when the activation navigation started by inspecting the `activationStart` milestone added to the Navigation Timing API. This should be very close to the `prerenderingchange` event if the implementation is performant.

A header like `Purpose: prefetch` is added to requests from prerendered pages. Therefore, if the page makes cross-origin requests, the cross-origin servers can see that the requests came from a prerendered page. Some user agents already add such a header to some existing prefetching features. Standardization discussion for this is happening at [Resource Hints #74](https://github.com/w3c/resource-hints/issues/74).

### Does this specification enable new script execution/loading mechanisms?

It provides a new way of initiating behavior previously available through Resource Hints. These behaviors are presently poorly specified. We are working to more formally explain them and address their security and privacy considerations (including in anticipation of the removal of third-party cookies from the web), though that is not strictly part of the speculation rules proposal.

### Does this specification allow an origin to access other devices?

No.

### Do features in this specification allow an origin some measure of control over a user agent’s native UI?

No.

### What temporary identifiers do the features in this specification create or expose to the web?

None known.

### How does this specification distinguish between behavior in first-party and third-party contexts?

We propose that prerendering can only be triggered by the main frame (first-party). Activation can also only happen on main frame navigations.

The loading of cross-origin subframes (third-party) in a prerendered page is deferred until activation.

### How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

We propose that private browsing works the same as a normal context (with no sharing of information between the contexts).

Browsers could choose to behave more conservatively, but doing so may make it possible to detect private browsing mode.

### Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

Not as yet, though we recognize that it cannot be considered complete without one.

We do discuss security and privacy considerations thoroughly in the relevant explainers, though they are naturally focused on the cross-origin cases. We will be porting those discussions into the overall [Prerendering Revamped](https://wicg.github.io/nav-speculation/prerendering.html) specification as that specification gets more concrete.

### Do features in your specification enable origins to downgrade default security protections?

No.
