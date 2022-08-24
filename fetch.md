# Cross-site preloading fetching modes

## Related issues and discussion

There is a long history of standards and implementation discussion around some of the problems that parts of this document aim to bring clarity to, namely, the fetching of speculative resources intended to be used by future navigations:

- [w3c/resource-hints: Specify processing model in terms of Fetch](https://github.com/w3c/resource-hints/issues/86)
- [w3c/resource-hints: Specify prerender processing model](https://github.com/w3c/resource-hints/issues/63)
- [whatwg/fetch: Speculative Request Flag](https://github.com/whatwg/fetch/pull/881)
- [whatwg/html: Add prefetch processing model & double-key cache protections](https://github.com/whatwg/html/pull/4115)

The above discussion revolves largely around `<link rel="prefetch">`, which generally has been for a single resource: sometimes a subresource, and sometimes a main navigation resource. In this document, we focus specifically on prefetching and prerendering, which are about the main navigational resource (and, in the case of prerendering, its subresources).

Our proposal, outlined below, is that when these requests are cross-site, they have the following properties:

- Fetched without credentials
- Fetched in a way that does not update or access the main HTTP cache or cookie jar
- Fetched with a limited amount of referrer information

These restrictions are all geared to protect the user's privacy and prevent any cross-site information sharing, of the type that is being prohibited by the ongoing [storage partitioning][] work. In the rest of this document we go into more detail into the above restrictions. We also describe how these restrictions are lifted when a preloaded resource is activated (i.e., when it is user-visibly navigated to).

_Note: none of these restrictions apply to **same**-site preloading. Same-site preloading does not have privacy concerns and is not impacted by [storage partitioning][]._

_Note: right now only cross-site prefetching is specified and implemented. So for pre**rendering**, this document mostly contains speculation and tentative proposals._

## Fetching with no credentials

Speculative navigation requests should in no way leak the user's identity to third-party origins. A consequence of this is that all cross-site preloading requests must be done with no credentials. (Here, "credentials" essentially means cookies: other HTTP credentials, such as HTTP basic auth certificates, currently cause preloading to fail.)

This must apply to all of the following:

- Top-level speculative resources
- Subresources under top-level speculative resources
- Nested browsing contexts and their subresources

For cross-site prefetching, where we only fetch the top-level resource, this is done through the [HTTP state partitioning](#http-state-partitioning) strategy mentioned below.

For cross-site prerendering, we are not yet sure on the strategy for subresources. It could either be to omit all credentials, or it could be to try a similar HTTP state partitioning approach.

### What if the site already has credentials?

If a given site already has credentials, then the preloaded page needs to [opt in](./opt-in.md); otherwise, preloading will immediately fail, discarding the response. This opt-in indicates that they are prepared to deal with their prefetched content being loaded with no credentials, which is a state that might not reflect the user's actual previous interaction patterns.

Currently, this opt in is not yet specified or implemented anywhere. Instead, we silently fail to do cross-site prefetch, if the destination site already has credentials.

### Credentials after activation

After activation, any future requests can be made with credentials.

Any credentials that arrived during the pre-activation period will be [merged](#http-state-after-activation) with existing credentials, as if they were acquired during a navigation that occurred at that time.

## HTTP state partitioning

To avoid cross-site information sharing about the user, cross-site speculative navigation requests must neither use nor modify any HTTP state that is observable to other pages. Here, "HTTP state" means the HTTP cache, plus credentials (~ cookies).

For example, if `a.com` prefetches `b.com`, this must not let `b.com` modify its own first-party cookies; this would allow `a.com` and `b.com` to communicate. Similarly, `b.com` must not be able to read its own first-party cookies, as this could give `b.com` the impression a specific user is visiting (even though the user has not yet expressed an affirmative intent to navigate).

To avoid this, during prefetching we create a temporary isolated [environment][] to serve as the top-level environment, with a new opaque origin as its origin. Then, all fetches that take place during the speculative navigation will utilize this environment to compute their [network partition key][] and [determine the HTTP cache partition][]. Since the key's primary identifier is the [top-level origin][] of the environment, this means we will be acting in a completely separate network partition for the duration of the preloading operation.

### HTTP state after activation

At the point of activation, the speculative HTTP state contained in our isolated partition is now safe to expose to the main partition that non-speculative pages use, since the user has clearly expressed their intent to navigate.

So far we have only thought through the correct behavior for prefetches. (Cross-site prerendering is in general not yet something we are confident in.) For them, we:

- Merge the isolated partition's cookies into the main partition, as if they had been received at the time of the activation via `Set-Cookie` headers;
- Allow, but do not require, merging in the HTTP cache partition's contents.

Note that usually this cookie merging will be straightforward, since [per the above](#what-if-the-site-already-has-credentials) we will currently only perform the initial prefetch when the site has no credentials. Thus, the only possibility of a merge conflict is if the user caused the site to gain credentials in the time between prefetching and activation.

The reason we do not require merging in the HTTP cache partition's contents is that the HTTP cache is in general an optimization, and doing this merging is likely to have marginal benefit for prefetches. In particular, the HTTP cache partition will only contain the single prefetched main-document, and often documents do not have cache-friendly headers anyway.

### Alternative: use a separate type of ephemeral cache

Instead of using the existing [network partition key][] infrastructure, we could have used a separate type of cache, probably an in-memory ephemeral one that is discarded after activation.

The main reason to avoid this is the complexity of reinventing new caching semantics. In particular, we would have to:

- determine a reasonable set of cache read/write semantics;
- explore how this relates to the non-yet-spec'ed memory cache and `<link rel="preload">` cache; and
- potentially create partitioning mechanics similar to those of the HTTP cache, for user privacy.

It also would be challenging to foster interoperability with the usage of this brand new cache, as we've found out from the memory cache and `<link rel="preload">` cache situation.

### Alternative: bypass the HTTP cache entirely

Another approach to this problem would be to override the [cache mode][] of all preloading requests to `"no-store"`. Fetching would behave as though HTTP cache were not present, and it would be impossible to contaminate any HTTP cache partitions observable to other pages.

The main downside of this approach is that we lose the ability to use any of the resources fetched during preloading, after activation. That is, we lose whatever benefits we could gain by having the ability to merge speculatively-cached resources into the main HTTP cache partition, should we decide to go that route. This is especially important if we do cross-site prerendering: if the actual prerendering browsing context is discarded (e.g. due to memory constraints), it would be ideal to keep the downloaded resources anyway, so as to provide at least some benefit.

This approach also doesn't have anything to say about credentials, whereas with our chosen approach we partition both cache and credentials state in the same way.

## Stripping referrer information

To preserve the user's privacy and prevent cross-site communication, there should be a limited amount of referrer information sent along with cross-site speculative navigation requests. In particular, it should not be possible to expose the full referrer path. Instead, the total referrer information will be limited to at most the referrer's origin.

We achieve this by requiring that the referring page be using a **sufficiently-strict referrer policy**, which is one that is at least as strict as the platform [default][default referrer policy] of `"strict-origin-when-cross-origin"`. So, it must be one of the following:

- `"strict-origin-when-cross-origin"`
- `"same-origin"`
- `"strict-origin"`
- `"no-referrer"`

A speculative navigation request that would be made with a referrer policy outside of this list will be ignored. (Browsers are free to let developers know about the issue through their developer tooling.)

### Referrer information on subresource requests

This proposal applies the referrer redaction described above only to top-level speculative navigation requests. That is, we don't override the referrer policy of any prerendered documents, in a way that would change how referrer information is sent to subresources. This is because any referrer information exposed from the prerendered document does not expose any information about the original referrer document. The most that a prerendered page could expose about its referrer page is the value of its own `document.referrer`, which is subject to the redaction described earlier in this section.

### Alternative: cap the referrer policy to `"strict-origin-when-cross-origin"`

One alternative to our sufficiently-strict referrer policy proposal above is to change any less-strict referrer policies into `"strict-origin-when-cross-origin"` as part of making the preloading request.

This would allow pages which otherwise set globally-lax referrer policies, such as `"unsafe-url"`, to perform cross-site preloads. Whereas with our current proposal, such preload requests are ignored.

The main downside of this is that deviates from developer intent. We think it's better to instead [introduce the ability to trigger preloads with a different referrer policy than your document uses](https://github.com/WICG/nav-speculation/issues/167).

## Using a privacy-preserving proxy

In addition to the above baseline requirements, we also want to offer the option for cross-site preloading to be done via an IP-anonymizing proxy. See the ["Anonymous Client IP"](./anonymous-client-ip.md) document for more.

[determine the HTTP cache partition]: https://fetch.spec.whatwg.org/#determine-the-http-cache-partition
[top-level origin]: https://html.spec.whatwg.org/multipage/webappapis.html#concept-environment-top-level-origin
[network partition key]: https://fetch.spec.whatwg.org/#network-partition-key
[environment]: https://html.spec.whatwg.org/multipage/webappapis.html#environment
[cache mode]: https://fetch.spec.whatwg.org/#concept-request-cache-mode
[default referrer policy]: https://w3c.github.io/webappsec-referrer-policy/#default-referrer-policy
[storage partitioning]: https://github.com/privacycg/storage-partitioning/
