# Loading mode support

Several subtypes of preloading introduce novel ways of loading content, which the destination site might not be prepared for. In such cases, we require that the response signal that they support the given loading mode, via the `Supports-Loading-Mode` header proposed here.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [HTTP header declaration](#http-header-declaration)
- [Use cases](#use-cases)
  - [Uncredentialed preloading](#uncredentialed-preloading)
  - [Cross-origin same-site prerendering](#cross-origin-same-site-prerendering)
  - [Non-preloading cases](#non-preloading-cases)
- [Future extensions](#future-extensions)
  - [An in-markup version](#an-in-markup-version)
  - [Application to subframes while prerendering](#application-to-subframes-while-prerendering)
- [Redirect handling](#redirect-handling)
- [Alternatives considered](#alternatives-considered)
  - [No declaration](#no-declaration)
  - [Opt-out only](#opt-out-only)
  - [Document policy](#document-policy)
- [Acknowledgments](#acknowledgments)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## HTTP header declaration

```http
Supports-Loading-Mode: uncredentialed-prefetch, uncredentialed-prerender
```

This is an [HTTP structured header][http-structured-header] which lists tokens indicating the loading modes the content is ready for. The tokens we so far envision are:

* `uncredentialed-prefetch`
* `uncredentialed-prerender`
* `credentialed-prerender`

## Use cases

### Uncredentialed preloading

Cross-site preloads intentionally obscure the user's identity, to avoid leaking it to sites that the user has not yet affirmatively indicated an intent to visit. See the [Cross-site preloading fetching modes](./fetch.md) document for more details. Because of this, the resulting responses cannot be personalized for the user. If such responses are directly shown to the user upon activation, the user will notice that they are not logged in (even if they should be), and other surprising behavior.

Pages designed with these restrictions in mind can "upgrade" themselves when they are activated, by personalizing based on data in unpartitioned storage and by fetching personalized content from the server. But existing web pages are unlikely to behave well with these restrictions today. (And, it is impractical for user agents to distinguish such pages.)

To resolve this problem, user agents must only preload pages which either:

* Have no stored credentials (for prefetch) or storage of any kind (for prerender); or
* Indicate that they are prepared to perform this sort of upgrade, by sending the appropriate `Supports-Loading-Mode` header value: either `uncredentialed-prefetch`, `uncredentialed-prerender`, or both.

_Note: these values are not currently implemented in Chromium._

### Cross-origin same-site prerendering

For prerendering, there is an additional complication when dealing with cross-origin destinations. Because the web's privacy boundary is site, we can send credentials and give storage access to such pages before activation. However, the web's _security_ boundary is the origin, not the site. So we need to ensure that pages cannot use prerendering to attack other origins—even same-site ones.

As a concrete example of what an "attack" might look like, consider an organization which provides both web hosting and document editing services. Furthermore, assume that whenever you render a document on the document editing service, the viewer's JavaScript code updates the user's list of recently-viewed documents. And finally, assume that the document editing service is not prerendering-aware, i.e. it has no code that checks [`document.prerendering`](./prerendering-state.md) to customize its behavior. Then, if we allowed `https://sites.example.com/bobs-star-wars-fan-site` to prerender `https://docs.example.com/public-list-of-best-star-wars-movies` with no opt-in, Bob's Star Wars Fan Site would be able to update the user's list of recently-viewed documents, pushing the List of Best Star Wars Movies document to the top.

To resolve this problem, we need to extend the previous section as follows:

* Prerendering a cross-site URL will perform the fetch, and only use the results if it contains `Supports-Loading-Mode: uncredentialed-prerender`
* Prerendering a cross-origin same-site URL will perform the fetch, and only use the results if it contains `Supports-Loading-Mode: credentialed-prerender`
* (Prerendering a same-origin URL does not have any restriction.)

_Note: as indicated previously, the first case here is not yet implemented in Chromium; for cross-site URLs, we instead just ignore the prerendering request._

With this framework in place, by default, Bob's Star Wars Fan Site's attempt to prerender the List of Best Star Wars Movies document will fail and have no effect. And eventually, `https://docs.example.com/` might update their code to be prerendering aware, by not modifying the user's list of recently-viewed documents while prerendering. Once they've made such updates, `https://docs.example.com/` can add the `Supports-Loading-Mode: credentialed-prerender` header, and now the prerendering will work—giving a fast navigation from Bob's Star Wars Fan Site, with no unintended side effects.

### Non-preloading cases

There are other contexts on the web platform where novel loading modes are introduced. One of these is [fenced frames](https://github.com/WICG/fenced-frame), which also will use the `Supports-Loading-Mode` opt-in.

## Future extensions

### An in-markup version

We believe it would also be possible to have a `<meta>` version of this opt-in, within the response body:

```html
<meta http-equiv="Supports-Loading-Mode"
      content="uncredentialed-prefetch, uncredentialed-prerender">
```

This would be processed only if it appears within the `<head>` element and no `<script>`, `<noscript>` or `<template>` tag appears before it. This means that the supported loading modes, if not declared in a response header, can be statically computed with use of an HTML parser without rendering or script execution. See [the meta processing model](./meta-processing.md) for details.

The main advantage here is that this may be easier to adopt. In order to make as much content as possible available for uncredentialed preloading, we would like to make it as easy as possible for authors to mark eligible content. We have heard from developers that many of them find it much easier to deploy changes that only affect content than changes which also require server behavior changes, even relatively straightforward ones. For example, these may be managed by different teams or not be possible at all. One example here is that GitHub Pages doesn't allow users to set response headers.

### Application to subframes while prerendering

Currently while prerendering, the loading of all cross-origin subframes are delayed. This prevents attacks similar to those described [above](#cross-origin-same-site-prerender). But of course, it has the cost that some of the benefits of prerendering are absent for such pages.

We could use `Supports-Loading-Mode` to allow subframes to indicate they are OK with being prerendered, using either the `credentialed-prerender` or `uncredentialed-prerender` variants.

It's not 100% clear this is necessary, because after [storage partitioning](https://github.com/privacycg/storage-partitioning/), the "attacks" on these cross-origin subframes would actually be on the subframe origin's partition within the top-level prerendered origin. Arguably, the top-level prerendered origin could be the one making decisions on behalf of its sub-partitions. If we want to start un-delaying cross-origin subframes in the future, we'll need to consider this question more carefully, and discuss it with the storage partitioning community.

## Redirect handling

This header only needs to be supplied by the final response in any redirect chain. For example, for the `credentialed-prerender` case, `https://example.com/` → `https://a.example.com/` without the header → `https://b.example.com/` with the header succeeds.

This is because checking the intermediate redirects does not gain anything. Once the request has been issued, any server-side behavior has already happened, and we will not process any client-side behavior for redirect responses.

## Alternatives considered

### No declaration

Why is a declaration needed at all? Why can't the document be fetched and loaded normally, just without credentials?

The origin may already have data in its unpartitioned storage, but from the above, our goal is to provide for preloading which does not grant access to it until the user actually navigates to the destination site. However, this may cause the content to load and behave differently than it would have with access to its unpartitioned storage. Then, when the prerendered document is preseneted, the user will observe any such differences as brokenness.

For example, an authenticated user or subscriber will observe that on navigation, that state is not reflected (they appear logged out or encounter a paywall). The user is likely to __blame the innocent destination site for this brokenness__. (Naturally, this is unlikely to be an issue if the origin has no existing cookies or other storage.)

The user agent could reload the page on navigation, but this would defeat the point of preloading.

If the user agent could detect brokenness, it could avoid this. However, this seems impossible to do in general, because:

* the server response could depend on the presence of cookies and other credentials
* client-side access can be detected, but it is unclear how to infer whether this corresponds to user-visible brokenness

It might be possible for the user agent to augment author declarations with a list of origins or documents known to behave well, as a browser feature. This would depend on identifying such sites in a fairly reliable way and providing a mechanism for users to reload if they observe brokenness. However, such a mechanism would have limitations and would necessarily not behave the same in all browsers. The web platform should provide a way to more predictably get the desired behavior.

### Opt-out only

Could an opt-out suffice? It would seem to make it easier to increase coverage.

In principle, yes. However, this would mean that content may become broken (as described above) and require authors to roll out an opt-out to simply restore the previous level of functionality. This seems problematic, especially since we anticipate a large fraction of the web would be affected.

Note that there is some precedent for opting out of a novel loading mode in `X-Frame-Options`, which lets content opt out of being loaded inside a frame. However, this model is widely seen as a mistake, and it would have been better to have been designed as an opt-in.

### Document policy

[Document policy][] provides a related mechanism, which allows a document to provide a set of behavior changes and restrictions it wishes to apply to itself in an HTTP response header, `Document-Policy`. The request may contain a `Sec-Required-Document-Policy` header, which indicates the minimum level of strictness for each policy that is required—otherwise the load will fail.

Document policy also defines a strict mechanism for inheritance of strict document policy (always inherited by subframes, declaration is required or load fails), but this is not flexible enough for the preferred behavior above. In particular the option of deferral wouldn't ordinarily make sense for document policy (since required policy and policy both cannot change), but do make sense for preloading, where the user may eventually navigate.

Document policy is also immutable, so either we would have to introduce a notion of mutable required policy and mutable policy, or we would have to define a policy named something like `initial-unpartitioned-storage` that doesn't change, but which only controls unpartitioned storage "initially". This is somewhat awkward and could lead to an explosion of "initial" vs "always" policies.

## Acknowledgments

@jeremyroman and @domenic are the primary authors of this explainer.

Thanks to @kinu, @yoavweiss, @clelland, and others, for their thoughts which contributed to this proposal.

[document policy]: https://github.com/w3c/webappsec-permissions-policy/blob/master/document-policy-explainer.md
[http-structured-header]: https://httpwg.org/http-extensions/draft-ietf-httpbis-header-structure.html
