# Cross-site prerendering

Building on our vision for [same-site prerendering](./prerendering-same-site.md), we would eventually like to enable prerendering of cross-site content.

None of this is implemented or specified in detail yet. But, we've spent some time thinking about it, and wanted to capture that process publicly.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [Privacy-based restrictions](#privacy-based-restrictions)
  - [Storage access blocking](#storage-access-blocking)
  - [Communications channels that are blocked](#communications-channels-that-are-blocked)
  - [Communications channels that match navigation](#communications-channels-that-match-navigation)
- [CSP integration](#csp-integration)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Privacy-based restrictions

In addition to the [restrictions for same-site prerendering](./prerendering-same-site.md#restrictions), cross-site prerendering has more privacy-based restrictions. In particular, prerendering is intended to comply with the [W3C Target Privacy Threat Model](https://w3cping.github.io/privacy-threat-model/). This section discusses the aspects of that threat model that are particularly relevant to the browsing context part of the story, and how the design satisfies them.

A prerendering browsing context can contain either a same-site or cross-site resource. Same-site prerendered content don't present any privacy risks, but cross-site resources risk enabling [cross-site recognition](https://w3cping.github.io/privacy-threat-model/#model-cross-site-recognition) by creating a messaging channel across otherwise-partitioned domains. For simplicity, when a cross-site channel needs to be blocked, we also block it for same-site cross-origin content. In some cases we even block it for same-origin content.

Because prerendered browsing contexts can be activated, they (eventually) live in the first-party [storage shelf](https://storage.spec.whatwg.org/#storage-shelf) of their origin. This means that the usual plan of [storage partitioning](https://github.com/privacycg/storage-partitioning) does not suffice for prerendering browsing contexts as it does for nested browsing contexts (i.e. iframes). Instead, we take the following measures to restrict cross-site prerendered content:

- Prevent communication with the referring document, to the same extent we prevent it with a cross-site link opened in a new tab.
- Block all storage access while content is prerendered.

If we allowed communication, then the prerendered content could be given the user ID from the host site. Then, after activation gives the prerendered page access to first-party storage, it would join that user ID with information from its own first-party storage to perform cross-site tracking.

If we allowed access to (unpartitioned) storage, then side channels available pre-activation (e.g., server-side timing correlation) could potentially be used to join two separate user identifiers, one from the referring site and one from the prerendered site's unpartitioned storage.

The below subsections explore the implementation of these restrictions in more detail.

### Storage access blocking

Prerendered pages that are cross-site to their referring site will have no access to storage.

We could attempt to address the threat by providing partitioned or ephemeral storage access, but then it is unclear how to transition to _unpartitioned_ storage upon activation. It would likely require some kind of web-developer-written merging logic. Completely blocking storage access is thus deemed simpler; prerendered pages should not be doing anything which requires persistent storage before activation.

This means that most existing content will appear "broken" when prerendered by a cross-site referrer. This necessitates an explicit opt-in to allow cross-site content to be prerendered, [discussed elsewhere](./opt-in.md). Such content might optionally "upgrade" itself to a credentialed view upon activation, as shown in the [example](#example) above.

For a more concrete example, consider `https://aggregator.example/` which wants to prerender this GitHub repository. To make this work, GitHub would need to add the opt-in to allow the page to be prerendered. Additionally, GitHub should add code to adapt their UI to show the logged-in view upon activation, by removing the "Join GitHub today" banner, and retrieving the user's credentials from storage and using them to replace the signed-out header with the signed-in header. Without such adapter code, activating the prerendering browsing context would show the user a logged-out view of GitHub in the top-level tab that the prerendering browsing context has been activated into. This would be a bad and confusing user experience, since the user is logged in to GitHub in all of their other top-level tabs.

As for the exact mechanism of this blocking:

- Asynchronous storage access APIs, such as IndexedDB, the Cache API, and File System Access's origin-private file system, will perform no work and have their corresponding promises/events delayed until activation.

- For synchronous storage APIs like `localStorage` and `docuemnt.cookie`, we are currently still discussing the best option, in [#7](https://github.com/WICG/nav-speculation/issues/7). The simplest idea would be to have them throw exceptions, but there may be more friendly alternatives that would allow prerendering to work on more pages without code changes.

### Communications channels that are blocked

- Prerendering browsing contexts have no reference to the `Window`, or other objects, of their referrer. Thus, they cannot communicate using [`postMessage()`](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage) or other APIs.
- `BroadcastChannel` behavior is modified in prerendering browsing contexts. Any messages sent to such a channel are queued up and only delivered after activation. Any messages received on the channel pre-activation are dropped.
- `SharedWorker` construction is delayed in prerendering browsing contexts. In particular, while the `new SharedWorker()` constructor returns immediately, no worker is started or connected to until after activation. Any messages sent to the `SharedWorker` pre-activation are buffered up and delivered upon activation. (And, since the `SharedWorker` is not connected to an actual shared worker pre-activation, no message can be received on it pre-activation.)
- Web locks APIs will return promises which wait to settle (and wait to do any lock-related work) until activation.
- TODO `ServiceWorker`?
- Fetches within cross-site prerendering browsing contexts, including the initial request for the page, do not use credentials. Credentialed fetches could be used for cross-site recognition, for example by:
  - Using the sequence of loads. The referring page could encode a user ID into the order in which a sequence of URLs are prerendered. To prevent the target from correlating this ID with its own user ID without a navigation, a document loaded into a cross-site prerendering browsing context is fetched without credentials and doesn't have access to storage, as described above.
  - The host creates a prerendering browsing context, and the prerendered site decides between a 204 and a real response based on the user's ID. Or the prerendered site delays the response by an amount of time that depends on the user's ID. Because the prerendering load is done without credentials, the prerendered site can't get its user ID in order to make this sort of decision.
- Sizing side channels: prerendering browsing contexts always perform layout based on the initial size of their referring browsing context, as its most likely that upon activation, they'll end up with that same size. However, further resizes to the referring browsing context are not used to update the size of the prerendering browsing context, as this could be used to communicate a user ID. For simplicity, we apply this sizing model to same-origin prerendered content as well.

### Communications channels that match navigation

As mentioned above, we prevent communications to the same extent we prevent it with a cross-site link opened in a new tab. In particular:

- The prerendered content's own URL and the referring URL are available to prerendered content to the same extent they're available to normal navigations. Solutions to link decoration will apply to both.

Note that since a non-activated prerendering browsing context has no storage access, it cannot join any information stored in the URL with any of the prerendered site's data. So it's only activation, which gives full first-party storage access, which creates a navigation-equivalent communications channel. This equivalence makes sense, as activating a prerendering browsing context is much like clicking a link.

## CSP integration

The [`navigate-to`](https://w3c.github.io/webappsec-csp/#directive-navigate-to) directive prevents navigations, which means that if prerendered content is prevented from being navigated to via this mechanism, then the corresponding prerendering browsing context will never be activated. This mostly falls out automatically from the CSP spec preventing navigations, but any prerendering APIs that explicitly expose the activation operation (such as [portals](https://github.com/WICG/portals/blob/master/README.md)) will need to account for it in their specification.

Note that `navigate-to` will prohibit navigations based on the URL of the link clicked (or similar), which corresponds to a prerendering browsing context's original URL (discussed [above](#navigation)). This means that given something like

```http
Content-Security-Policy: navigate-to https://a.example
```

and markup such as

```html
<link rel="prerender2" href="https://a.example/redirects-to-another-origin">

<script>
location.href = 'https://a.example/redirects-to-another-origin';
</script>
```

then the navigation will be allowed, _even though_ the prerendering browsing context could be pointing to an origin besides `https://a.example`. In other words, prerendering does not change the behavior of `navigate-to`, despite allowing the browser to know more information about the eventual navigation destination.
