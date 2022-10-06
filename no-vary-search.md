# The `No-Vary-Search` HTTP response header

Caching is useful for making web pages load faster, and thus creating better user experiences. Prominent caches on the web platform include the HTTP cache, as well as the subjects of this repository, the prefetch and prerender caches.

One of the most important cache keys for web resources is the resource's URL. However, sometimes multiple URLs can represent the same resource. This leads to caches not always being as helpful as they could be: if the browser has the resource cached under one URL, but the resource is then requested under another, the cached version will be ignored.

This proposal tackles a specific subset of this general problem, for when a resource has multiple URLs which differ only in certain query components. Via a new HTTP header, `No-Vary-Search`, resources can declare that some or all parts of the query can be ignored for cache matching purposes. For example, if the order of the query parameter keys should not cause cache misses, this is indicated using

```http-header
No-Vary-Search: key-order
```

If the specific query parameters (e.g., ones indicating something for analytics) should not cause cache misses, this is indicated using

```http-header
No-Vary-Search: "utm_source", "utm_medium", "utm_campaign"
```

And if the page instead wants to take an allowlist-based approach, where only certain known query parameters should cause cache misses, they can use

```http-header
No-Vary-Search: *; except=("productId")
```

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [Goals](#goals)
- [Non-goals](#non-goals)
- [Prior art](#prior-art)
- [Use cases](#use-cases)
  - [Avoiding unnecessary cache mismatches due to inconsistent referrers](#avoiding-unnecessary-cache-mismatches-due-to-inconsistent-referrers)
  - [Customizing server behavior](#customizing-server-behavior)
  - [Carrying data that is or can be processed by client-side script only](#carrying-data-that-is-or-can-be-processed-by-client-side-script-only)
  - [Carrying data not yet determined at the time of preloading](#carrying-data-not-yet-determined-at-the-time-of-preloading)
- [Detailed design](#detailed-design)
  - [The header](#the-header)
  - [Integration with…](#integration-with)
    - [… preloading caches](#-preloading-caches)
    - [… the Cache API](#-the-cache-api)
    - [… other web platform caches](#-other-web-platform-caches)
    - [… HTTP caches](#-http-caches)
  - [Navigated-to pages](#navigated-to-pages)
    - [Prerendering activation](#prerendering-activation)
  - [Interaction with redirects …](#interaction-with-redirects-)
    - [… at the HTTP and Cache API level](#-at-the-http-and-cache-api-level)
    - [… for other browser caches](#-for-other-browser-caches)
  - [Interaction with storage partitioning](#interaction-with-storage-partitioning)
- [Alternatives considered](#alternatives-considered)
- [Extensibility](#extensibility)
  - [More complex no-vary rules](#more-complex-no-vary-rules)
  - [`No-Vary-Path`](#no-vary-path)
  - [A referrer hint](#a-referrer-hint)
  - [A `<meta>` version](#a-meta-version)
- [Security and privacy considerations](#security-and-privacy-considerations)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Goals

- Allow caches to avoid keying on the order of URL query parameter keys

- Allow caches to avoid keying on specifically-named URL query parameters

- Allow caches to avoid keying on all URL query parameters, or all-but-some-specifically-named URL query parameters

## Non-goals

- Allow more complicated keying rules than the above, e.g. "treat `key` and `KEY` as equivalent"; or, "treat `value1` and `value2` as equivalent for `key`, but treat `value3` differently"; or, "order doesn't matter for most parameters, but the position of the `key` parameter matters"; or, "allow the `width` parameter to match as long as its value is within 100 of the already-cached URL's `width` value". Some of these [seem possible as future extensions](#more-complex-no-vary-rules), but we are not designing around them.

- Support non-standard query parameter structures, e.g. `?color=red;size=large` with a `;` delimiter instead of a `&`. We will use the [`application/x-www-form-urlencoded` format](https://url.spec.whatwg.org/#concept-urlencoded) supported by the URL Standard.

- Allow caches to avoid keying on other parts of the URL, notably the path. Although this could be useful, we think it would best be done via [an additive separate solution](#no-vary-path).

## Prior art

This proposal takes some of its inspiration from the existing [`Vary`](https://httpwg.org/specs/rfc9110.html#field.vary) HTTP header, which lets servers indicate what _header names_ should be _included_ when constructing the cache key. Unlike for headers, by default responses vary on their URL (including query string), so our proposal uses the `No-Vary-` prefix to show how it's indicating which query parameters should be _excluded_ when constructing the cache key. We see these two headers, the existing `Vary` and our proposed `No-Vary-Search`, as part of a general cache-key-construction mechanism, and ideally all places that respect the former will also respect the latter. (However, if they don't, the consequence is just fewer cache hits. So it isn't mandatory that all parts of the ecosystem immediately upgrade to support `No-Vary-Search`.)

It is widely recognized that query parameters might interfere with constructing an appropriate cache key. Specific CDNs have solutions for this in place already. For example, [CloudFlare](https://developers.cloudflare.com/cache/about/cache-keys) allows almost the same level of customization we are proposing here, with their `include` and `exclude` settings which can be given query string parameter names or `*`. (Their documentation does not give any indication of how they treat query parameter ordering.) And [Amazon CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/QueryStringParameters.html#query-string-parameters-optimizing-caching) lets you pick an allowlist of query parameters to cache based on, with the optional of ignoring all of them for caching purposes. Indeed, if you just [search for "cache vary query parameters"](https://www.google.com/search?q=cache+vary+query+parameters), you get a large variety of technical documentation on similar solutions throughout the tech stack. Although our proposal is aimed at browsers, we are optimistic that CDNs, proxies, and other parts of the HTTP ecosystem might be able to use the information in this header in addition to their vendor-specific solutions.

Finally, the web platform's [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache) (often used with service workers) combines the resource-specified `Vary` header with a caller-specified [`ignoreSearch` option](https://developer.mozilla.org/en-US/docs/Web/API/Cache/match) which allows ignoring all query parameters when performing a cache match. As discussed [below](#-the-cache-api), we plan to integrate `No-Vary-Search` with the cache API's functionality in this way.

## Use cases

We've found several examples of scenarios where data is carried by the query string, but authors would prefer that it does not affect caching:

### Avoiding unnecessary cache mismatches due to inconsistent referrers

In some circumstances, referrer pages may append spurious query parameters, or may use a non-canonical ordering of the query parameters as part of their process of constructing a URL referring to your page. This then causes unnecessary cache misses. Although this is usually fixable when the referrer page is your origin, it isn't fixable in the general case. And even for your own origin, legacy code might be hard to upgrade.

### Customizing server behavior

In some cases, query parameters can be used to modify server behavior, in a way that does not affect the end product. For example, requesting load-balancing to a particular instance; or, enabling server-side debug logging for a request; or, changing the priority of a request. Such customizations generally should not cause future cache misses. Although it would be ideal to communicate this information via request headers, not all places on the web platform allow customizable request headers. (For example, `<a>` or `<iframe>` elements do not.)

### Carrying data that is or can be processed by client-side script only

Some examples:

- Analytics data, e.g. what marketing campaign led the user to the destination.
- Where the user should be redirected to after some action is complete, e.g. a login process.
- Some detail to highlight on the page, e.g. map coordinates to zoom to or a product variant to emphasize.

Although in theory such data could be passed via the fragment instead of query string, prevailing practice often uses the query string. Additionally, preloading changes the calculus here: a page might want to do server-side processing if possible, but client-side processing if doing so would unlock the fast-loading benefits of preloading.

_Note: analytics, where you carry generic data such as the marketing campaign or referring source, is different than [navigational tracking](https://privacycg.github.io/nav-tracking-mitigations/#terminology), which passes along user identifiers. Nothing about this proposal is intended to aid navigational tracking, and we expect it to be fully compatible with future and [currently-deployed mitigations](https://privacycg.github.io/nav-tracking-mitigations/#deployed-mitigations) for navigational tracking. See more discussion in our [privacy considerations](#security-and-privacy-considerations)._

Another use case for this is entirely client-side-rendered skeleton pages. However, we're not focused on such cases, since they often use the path component to carry the variable information. See [future work on `No-Vary-Path`](#no-vary-path) for more discussion.

### Carrying data not yet determined at the time of preloading

The most prominent example here is analytics. Consider:

```html
<script type="speculationrules">
{
  "prerender": [{
    "source": "list",
    "urls": ["/articles/new-underwater-phone"]
  }]
}
</script>

<a href="/articles/new-underwater-phone?via=heroimage">
  <img src="underwaterphone.jpg" alt="A phone, underwater!">
</a>

<a href="/articles/new-underwater-phone?via=headline">New underwater phone, just released!</a>
```

When the page loads, we don't know yet whether the user will click on the hero image or the headline link. So it's useful to prerender the page with no query parameter, and then later [communicate that information](#prerendering-activation) once the user clicks on a link.

## Detailed design

### The header

The `No-Vary-Search` header is a [HTTP structured field](https://www.rfc-editor.org/rfc/rfc8941.html) whose value must be a list. The list can contain either predefined [tokens](https://www.rfc-editor.org/rfc/rfc8941.html#name-tokens), which have special behavior, or [strings](https://www.rfc-editor.org/rfc/rfc8941.html#name-strings), which indicate query parameters not to vary on. The special tokens are:

- `key-order`: indicates the order of the query parameter keys should be ignored when constructing the cache key. (As they were canonicalized using [`URLSearchParams`'s `sort()`](https://url.spec.whatwg.org/#dom-urlsearchparams-sort).)

- `*`: indicates all query parameters should be ignored when constructing the cache key. This can be supplemented by a list-of-strings-valued `except=()` [parameter](https://www.rfc-editor.org/rfc/rfc8941.html#name-parameters), which effectively allows indicating "_only_ vary on the given parameters".

If an unknown or invalid construct is encountered, e.g. a non-list value, or an unknown token, then the header is treated as if it is omitted. This is a good safe default, since it just causes more cache misses, which are less harmful than erroneous cache hits.

Note that if you use `*`, additionally using string values in the list is pointless, and those string values will be ignored. I.e., `No-Vary-Search: *, "foo"` is equivalent to `No-Vary-Search: *`, and the same goes for `No-Vary-Search: *;except=("foo"), "foo"`.

### Integration with…

#### … preloading caches

This repository contains specifications for in-memory URL-keyed caches for [prefetch records](https://wicg.github.io/nav-speculation/prefetch.html#document-prefetch-records) and [prerendering browsing contexts](https://wicg.github.io/nav-speculation/prerendering.html#document-prerendering-browsing-contexts-map). This proposal updates the key construction and matching procedure for these caches.

_Note: our [intent](https://github.com/WICG/nav-speculation/issues/170), not yet reflected in the specs, is for these caches to respect at least some of the general `Vary` header semantics._

#### … the Cache API

The [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache) already respects the `Vary` header when doing its cache matching, per [special handling in its spec](https://w3c.github.io/ServiceWorker/#request-matches-cached-item). This proposal adds similar special handling for `No-Vary-Search`.

The existing `ignoreVary` option to [`cache.match()`](https://developer.mozilla.org/en-US/docs/Web/API/Cache/match) will _not_ affect the processing of `No-Vary-Search`. `ignoreVary` is useful for increasing the default cache hit rate, by ignoring the requirements of the `Vary` header; having it decrease the default cache hit rate when applied to responses with `No-Vary-Search` headers would be surprising.

The existing `ignoreSearch` option to `cache.match()` will override the effect of `No-Vary-Search`; that is, if `ignoreSearch` is specified, then `No-Vary-Search` is ignored.

We could contemplate adding an `ignoreNoVarySearch` option to `cache.match()` in the future, but are not yet aware of any use cases for that level of customization.

#### … other web platform caches

There are several other URL-keyed caches on the web platform. The ones we are aware of are:

- The [list of available images](https://html.spec.whatwg.org/#the-list-of-available-images)
- [Module maps](https://html.spec.whatwg.org/#module-map)
- [Shared workers](https://html.spec.whatwg.org/#shared-workers-and-the-sharedworker-interface:concept-sharedworkerglobalscope-constructor-url)
- [Resources preloaded via `<link rel="preload">`](https://html.spec.whatwg.org/#map-of-preloaded-resources)

The proposal plans to update cache key computation for these caches as well.

Note that these caches are keyed by _request_ URL, whereas `No-Vary-Search` is a property of the _response_. See [below](#-for-other-browser-caches) for discussion on how this plays out.

#### … HTTP caches

The proposal augments [RFC 9111](https://httpwg.org/specs/rfc9111.html#constructing.responses.from.caches)'s notion of "Constructing Responses from Caches", providing a mechanism to relax the requirement of "The presented effective request URI \[sic] and that of the stored response match" in well-defined ways.

Since everything about the HTTP cache is best-effort, using `No-Vary-Search` will not guarantee additional cache hits. As such, browsers might implement HTTP cache integration after this feature has already proven its worth on, e.g., preloading caches.

### Navigated-to pages

When navigating to a URL which can be matched with a cached resource via `No-Vary-Search`, we still treat the resource _as if_ it were fetched from the target URL, and not from the originally-cached URL. For example:

- Service workers and resource timing APIs see fetches go by aimed at the target URL.
- Once the document is constructed and displayed:
  - `location.href` is the navigated-to response URL.
  - Any subresource fetches are done with a `Referer` header pointing to the navigated-to response URL.

In other words, this proposal purely modifies how URL matching works on the cache layer, allowing certain headers and body to match a given request URL, when previously they were not allowed to.

#### Prerendering activation

The above story gets slightly more complicated for prerendering, because the point of the prerender "cache" is to allow much more processing of the response than just supplying its headers and body. In particular, we will construct the [prerendering browsing context](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context) and its associated document based on the originally-requested URL, but later it could be activated with a different final URL.

For example, consider the [previous underwater phone article example](#carrying-data-not-yet-determined-at-the-time-of-preloading), assuming that `/articles/new-underwater-phone` responds with `No-Vary-Search: "via"`. If the browser chooses to use the `<script type="speculationrules">` to prerender `/articles/new-underwater-phone`, then that resource will be fetched and prerendered with no query parameters. Later, the user might click on the hero image, at which point we know the "real" URL that should be shown to the user is `/articles/new-underwater-phone?via=heroimage`.

To resolve this, we specify that prerendering [activation](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context-activate) involves changing the page's URL before firing the `prerenderingchange` event. This URL change is done using the [URL and history update steps](https://html.spec.whatwg.org/#url-and-history-update-steps), i.e. the same mechanism underlying `history.replaceState()`.

Concretely, this means:

- While being prerendered, the document's URL (which affects, e.g., `location.href`, the `Referer` of outgoing fetches, etc.) will be the originally-prerendered URL.
- After prerendering activation, the document's URL is updated to the actually-navigated-to URL. This means further reads from `location.href`, or outgoing `Referer`s, etc., will use this new URL.

With this setup, prerendered pages which care about a given query parameter, but don't want mismatches to prevent a prerender, can delay processing of the query parameter until activation time. For example:

```js
document.addEventListener("prerenderingchange", () => {
  const via = (new URLSearchParams(location.search)).get("via");
  analytics.send("via", via);
});
```

Note that both the prerendering feature and the use of `No-Vary-Search` is opt-in, so pages won't be surprised by this extra complication.

### Interaction with redirects …

Any mechanism for modifying how URLs are processed needs to be precise about whether it's dealing with _request_ URLs, or _response_ URLs, which can differ when HTTP redirects are involved.

#### … at the HTTP and Cache API level

For the HTTP cache itself, the answer is clear, since for each each individual cache lookup, the request and response URL are the same. `No-Vary-Search` does not change this. It allows a cache entry that was originally created from one request/response URL to be used to fulfill a cache lookup for a different request/response URL; it does _not_ do anything like letting a single cache lookup give back a response with a different URL.

This means that in a redirect chain, the header can be used at any or all points along the chain, e.g. one could see the following sequence of HTTP messages:

- Request `/apple-watch-ulatr`
- When looking up `/apple-watch-ulatr` in the cache, retrieve a response that was originally constructed from `/apple-watch-ulatr?utm_source=homepage` with `No-Vary-Search: "utm_source"`, whose status code at the time was `301` with `Location: /apple-watch-ultra?utm_source=homepage`.
- When looking up `/apple-watch-ultra?utm_source=homepage` in the cache, retrieve a response that was originally constructed from `/apple-watch-ultra?utm_source=twitter` with `No-Vary-Search: "utm_source"`.
- The result is the user looking at `/apple-watch-ultra?utm_source=homepage`, constructed from a previously-cached visit to `/apple-watch-ultra?utm_source=twitter`.

Note that, in terms of what the user sees in their URL bar, this is probably not the same result as would have been gotten without `No-Vary-Search`! That probably would have involved `/apple-watch-ulatr` redirecting to `/apple-watch-ultra`, with no query parameters showing up in the URL bar. The site has traded off nice URLs and accurate `utm_source` values, in favor of better cache utilization. If this is not desired, the site could avoid using `No-Vary-Search` on redirect responses, or it could fix up the user-facing URL using `history.replaceState()` shortly after loading. (The latter might be good practice anyway!)

The same reasoning applies to the [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache), which follows HTTP semantics.

#### … for other browser caches

For other browser caches, how `No-Vary-Search` applies across redirects is not as obvious, since they collapse redirect processing. For example, the shared worker cache is keyed by request URL, and contains `SharedWorkerGlobalScope` instances contructed from the response body and URL that ultimately results from following all the redirects. There is no opportunity to follow along the whole chain of redirects each time we do a cache lookup.

For these cases, we only account for the `No-Vary-Search` header corresponding to the cache key URL, which is always (to our knowledge) the request URL. For example, consider a situation where `/worker.js` redirects to `/worker-v2.js`, preserving any query parameters as part of the redirect. Then:

- If `/worker.js` sends `No-Vary-Search: "debuglog"`, then `new SharedWorker('/worker.js?debuglog=1')` followed by `new SharedWorker('/worker.js?debuglog=0')` will connect to the same shared worker, which was originally created from `/worker-v2.js?debuglog=1`.

- If `/worker-v2.js` sends `No-Vary-Search: "debuglog"`, but `/worker.js` does not, then `new SharedWorker('/worker.js?debuglog=1')` followed by `new SharedWorker('/worker.js?debuglog=0')` will spin up two separate workers, derived from `/worker-v2.js?debuglog=1` and `/worker-v2.js?debuglog=0` respectively.

### Interaction with storage partitioning

This proposal takes place fully within the bounds of the [client side storage partitioning](https://github.com/privacycg/storage-partitioning/) work. It is only about calculating the cache key within a given partition. It does not affect the computation of the partition key itself.

## Alternatives considered

`<link rel="canonical">` and its `Link` header counterpart could cover some of the use cases given here, if we expanded them to modify cache-matching semantics. Such expansion would likely have compatibility issues, given the large existing deployment of `<link rel="canonical">`. However, this only works for the simplest cases, such as `https://example.com/?k=v` saying that its canonical URL is `https://example.com/`, and then later being used to fulfill a request to `https://example.com/`. This does not allow a `https://example.com/?k=v1` response to fulfill a request for `https://example.com/?k=v2`, since to do so, we'd need to have previously requested `https://example.com/?k=v2` and seen that it has the same canonical URL as the stored `?k=v1` variant.

For same-origin cases, it might be possible for the referrer to indicate when query parameters are insignificant (or more generally, that substituting one URL for another is acceptable). This wouldn't be workable for cross-origin uses, however, for security reasons. See the section on a future [referrer hint](#a-referrer-hint) for more on when a referrer-based variant might be useful _in addition_ to a header-based variant.

The proposed solution could be given a narrower scope, such a header respected only by the preloading caches. We're open to this if necessary, but we think there's enough evidence of this being a larger problem that it's worth tackling other caches at the same time.

The response header could be flipped, i.e. `Vary-Search`, so as to better match `Vary`. We chose the `No-Vary-Search` framing because it means that the "empty" default state matches existing HTTP caching semantics (i.e., that the response varies by all query parameters). A `Vary-Search` version would probably need to have different behavior when the header is absent (vary on everything) vs. when the header is present but empty (vary on the empty list, i.e. nothing), which seems awkward.

The name could be `No-Vary-Query`, instead of `No-Vary-Search`. We chose "search" over "query" in the API because that is already exposed to the web platform through APIs such as `location.search`, `url.search`, `url.searchParams`, and `URLSearchParams`. (At the same time, we've continued talking about "query parameters" and the URL's "query string", since [that is what specs do](https://url.spec.whatwg.org/#concept-url-query). In other words, we stick with the existing mismatch between developer API and specification concepts.)

## Extensibility

The above proposal covers everything that we want to include in an initial version of this feature. However, a number of potential future extensions have come up in discussion, which we document here to ensure that the feature is sufficiently extensible to allow them.

### More complex no-vary rules

As mentioned in the [non-goals section](#non-goals), it's possible to imagine a variety of complex matching rules for treating different query strings equivalently. The structured header format we're using allows some extensibility in this regard, if we decide such non-goals should become goals in the future. For example:

- We could allow case-insensitivity of a given query parameter, using syntax like `No-Vary-Search: "color";value-case-insensitive=?1`.

- We could allow restrictions on the value space, using syntax like `No-Vary-Search: "color";value-regexp="(?:blue|azure)"`.

- We could allow treating multiple keys as the same key, using syntax like `No-Vary-Search: ("color", "colour")`.

- We could allow order-insensitivity for _values_, not just keys, using a `value-order` token. (This would treat `/a?x=y&x=z` the same as `/a?x=z&x=y`.)

We think capabilities such as these serve less urgent [use cases](#use-cases) than what we have so far, and so don't plan on supporting them now. But it's good to know there's room for them in the future.

### `No-Vary-Path`

Many of the arguments for avoiding cache misses on differing query parameters, also apply to avoiding cache misses on differing paths. This is most prominent in the case of client-rendered single-page applications, where e.g. `/products/123` and `/products/456` might both have the same HTTP response, containing the skeleton product page, with their differing content being done via client-side rendering.

Even for applications that are not usually client-side rendered, such a pattern might be beneficial specifically when combined with prerendering. For example, on a product search results page, you might not be confident enough to prerender any given product page, but you could instead prerender a generic "skeleton" product page such as `/products/skeleton` which, upon [prerendering activation](#prerendering-activation), performs client-side rendering for the product-specific details. Although such patterns are possible with `No-Vary-Search` as long as the variable parts of your URL are encoded as query parameters, they're not envisioned as a primary use case.

We think these use cases are best addressed by a future addition, similar to `No-Vary-Search` in spirit but different in details. We call this hypothetical future proposal `No-Vary-Path`.

In particular, splitting apart query and path handling makes sense because their in-practice semantics are very different. Although at some level both are opaque strings, in various parts of the HTTP ecosystem (e.g. server runtimes, CDNs, URL APIs, etc.) paths are treated as an ordered series of slash-delimited strings, and queries are treated as a usually-unordered multimap. So the syntax for specifying how a path would contribute to key calculation, versus a query, would likely be different. (Concretely, we suspect path handling would be based on [URL patterns](https://github.com/WICG/urlpattern), which are good for describing varying paths but bad for describing varying queries.)

The security considerations for `No-Vary-Path` _might_ be trickier than [those for `No-Vary-Search`](#security-and-privacy-considerations), given the existence of shared hosting environments that are sometimes sharded by path alone. Although path is not usually recognized as a security boundary on the web platform, some features like [service workers](https://w3c.github.io/ServiceWorker/#path-restriction) have decided to add some path-based restrictions, so if we explore `No-Vary-Path` we'll need to carefully study their discussions and conclusions.

Any future work on `No-Vary-Path` could benefit from the infrastructure work we do on `No-Vary-Search`, since it would have the same [integrations](#integration-with) and a generally similar processing model.

### A referrer hint

For the preloading case, the fact that we don't know whether a preloaded page considers query parameters important until the response comes back with its `No-Vary-Search` header causes a tradeoff. Consider this page:

```html
<script type=speculationrules>
{
  "prefetch": [{
    "source": "list",
    "urls": ["/products"],
    "score": 0.1
  }]
}
</script>
<a href="/products?id=123">click me</a>
```

Here, the `"score": 0.1` value is [meant to indicate](./triggers.md#scores) that the browser _may_ prefetch the given URL, and not that it _should_ prefetch the given URL. So, the browser probably won't prefetch `/products` on page load.

But, let's say the user presses down on the link. Now it seems pretty likely that `/products?id=123` is going to be visited, so it might be a good time to prefetch `/products`. After all, `/products` might come back with `No-Vary-Search` indicating that the `id` query parameter is unimportant.

We now have two paths:

1. `/products` _does_ have `No-Vary-Search: "id"`. For example, `/products?id=123` means to render the products view, and use client-side script to highlight the `X`th product. Then, our prefetch was great.
1. `/products` _does not_ have `No-Vary-Search: "id"`. For example, `/products` is an index listing all the products, whereas `/products?id=123` is a specific product page. Then, our prefetch was wasted, and we need to go fetch the separate `/products?id=123` page.

Also consider what happens if the headers for `/products` have not come back by the time the user releases the press, i.e. confirmed the intent to navigate. Do we wait on `/products` to finish? This makes (1) better and (2) worse. Or do we start a concurrent fetch to `/products?id=123`? This makes (1) worse and (2) better.

To solve this, we could have the speculation rules syntax provide a hint for what it expects the `No-Vary-Search` value to be. We would still have to verify the result (at least in cross-origin cases, for security; and proably in same-origin cases too, to avoid weird bugs). But it would help feed into the heuristics in such "may preload" cases.

Any solution in this area is probably best thought through together with the design work on [document rules](./triggers.md#document-rules), [scores](./triggers.md#scores), and maybe [`No-Vary-Path`](#no-vary-path), since they would all likely be used together.

### A `<meta>` version

As with all HTTP headers, sometimes it can be difficult for developers to add headers to their pages, and they instead would prefer a markup-based in-document version. The most natural way to do this would be `<meta http-equiv="No-Vary-Search">` with the same value space.

This would be a bit messy, as it would cause the various [integrations](#integration-with) to need to look into the response body to find this signal. For example, to our knowledge this would be the first time the HTTP cache knew anything about HTML. We would mitigate this by requiring the signal to be early in the document (picking some cutoff, say between 1–16 KiB), and giving a clear detection algorithm that does not require an entire browser or HTML parser (similar to [that envisioned for `<meta http-equiv="supports-loading-mode">`](./meta-processing.md)).

We're hopeful a response header will suffice, instead of needing to go this route. But we'll listen for feedback on the deployability, and revisit this option as necessary.

## Security and privacy considerations

Security-wise, the main risk to be aware of is the impact of mismatched URLs. In particular, this could cause the user to see a response that was originally fetched from a URL different from the one displayed when they hovered a link, or the URL displayed in the URL bar.

However, since the impact is limited to query parameters, this does not cross the relevant security boundary, which is the origin. (Or perhaps just the host, from [the perspective of security UI](https://url.spec.whatwg.org/#url-rendering-simplification).) Indeed, we already given origins complete control over how they present the (URL, reponse body) pair, including on the client side via technology such `history.replaceState()` or service workers.

For privacy, as [mentioned previously](#carrying-data-that-is-or-can-be-processed-by-client-side-script-only), this proposal is adjacent to the highly-privacy-relevant space of [navigational tracking](https://privacycg.github.io/nav-tracking-mitigations/#terminology), which often uses query parameters to pass along user identifiers. However, we believe this proposal itself does not have privacy impacts. It does not interfere with [existing navigational tracking mitigations](https://privacycg.github.io/nav-tracking-mitigations/#deployed-mitigations), or any known future ones being contemplated. Indeed, if a page were to encode user identifiers in its URL, the only ability this proposal gives is to _reduce_ such user tracking by preventing server processing of such user IDs (since the server is bypassed in favor of the cache).
