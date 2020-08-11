# Alternate Loading Modes

(Thanks to @domenic, @kinu, @yoavweiss, @clelland, and others, for their thoughts which contributed to this proposal.)

In order to making the experience of loading on the web faster, user agents employ prefetching and prerendering techniques. However, making cookies and other credentials available to the origin server or script may be inconsistent with the privacy objectives of the user or of the referring site.

First, consider the __fetch__ of the resource. User agents would ideally prefetch the content in a way that does not identify the user. For example, the user agent could:

* send a request without credentials (e.g., no `Cookie` or `Authorization` request header)
* establish the connection from a different client IP address (e.g., using a proxy server or virtual private network, if available)
* use a previously fetched response, including one previously fetched by a third party if it can be authenticated

However, because this (intentionally) obscures the user's identity, the response document cannot be personalized for the user. If it is used when the user navigates, the user will notice that they are not logged in (even if they should be), and other surprising behavior. A page designed with this in mind could "upgrade" itself when it loads, by personalizing the page based on data in unpartitioned storage and by fetching personalized content from the server.

Second, consider __prerendering__ the page. User agents would ideally allow HTML parsing, subresource fetching, and script execution in a way that does not identify the user or cause user-visible annoyance. For example, the user agent could:

* apply mitigations as above to subresource and scripted fetches
* deny scripted access to unpartitioned storage, such as cookies and IndexedDB
* deny permission to invoke `window.alert`, autoplay audio, and other APIs inappropriate at this time

In this case, not only is the HTML resource not personalized, but script will observe restrictions that would not ordinarily apply until navigation actually occurs. A page designed with this in mind could tolerate this at prerender time, and "upgrade" itself on navigation by accessing storage or fetching from the network.

Since existing web pages are unlikely to behave well with these restrictions today, and it is impractical for user agents to distinguish such pages, we propose a lightweight way for a page to declare that it is prepared for this and will, if necessary, upgrade itself when it gains access to unpartitioned storage and other privileges.

There has been previous discussion along these lines in [w3c/resource-hints#82](https://github.com/w3c/resource-hints/issues/82#issuecomment-536492276). (It also proposes a new `prenavigate` hint; defining triggers for these loading modes is not yet part of this proposal.)

## Table of contents

- [Declaration](#declaration)
- [JavaScript API](#javascript-api)
- [Request header](#request-header)
- [Risks](#risks)
- [Alternatives considered](#alternatives-considered)

## Declaration

```
// HTTP response header
Supports-Loading-Mode: uncredentialed-prefetch, uncredentialed-prerender

// HTML meta tag
<meta http-equiv="Supports-Loading-Mode"
      content="uncredentialed-prefetch, uncredentialed-prerender">
```

This is an [HTTP structured header][http-structured-header] which lists tokens indicating the loading modes the content is ready for. They have the following proposed meaning:

<dl>
  <dt><code>default</code></dt>
  <dd>Implied, even if not listed. Baseline standard behavior.</dd>

  <dt><code>uncredentialed-prefetch</code></dt>
  <dd>The resource is suitable for any user who meets the cache conditions. Either it is not personalized, or it includes script to modify the document to reflect credentialed state (e.g., to show the user's logged-in state). However, access to credentials will be available when the document loads and script executes.</dd>

  <dt><code>uncredentialed-prerender</code></dt>
  <dd>Implies <code>uncredentialed-prefetch</code>. The resource can be loaded without access to its credentials and storage. Access to certain other APIs may be limited in this state. Either it is not personalized based on credentials, or it includes script to modify the document when the loading state changes to permit it.</dd>
</dl>

The `<meta>` tag is processed only if it appears within the `<head>` element and no `<script>` tag appears before it.
This means that the supported loading modes, if not declared in a response header, can be statically computed with use of an HTML parser without rendering or script execution.

Blocking subframes which do not make this declaration is likely to make adoption more difficult. Ideally the author would be able to make as few declarations as possible to opt in, as long as this doesn't break too much. Fundamentally, there are three basic options here:
* subframe load fails
* subframe load is deferred until navigation
* subframe load proceeds

And there are several different scenarios:
* same-origin subframe, declaration present
* same-origin subframe, declaration absent
* cross-origin subframe, declaration present
* cross-origin subframe, declaration absent

> TODO: settle on what to do in each of these cases.

## JavaScript API

Script can observe and react to changes in the loading mode, if applicable. For example, it can observe a change from `uncredentialed-prerender` to `default` when a user navigates to the prerendered document. This can be used to defer personalization and logic which are not necessary for prerendering.

```js
function afterPrerendering() { /* ... */ }

if (!document.loadingMode || document.loadingMode.type === 'default') {
    afterPrerendering();
} else {
    document.addEventListener('loadingmodeechange', () => {
        if (document.loadingMode.type === 'default')
            afterPrerendering();
    });
}
```

Script can also observe this by using APIs particular to the behavior they are interested in. For instance, the [`document.hasStorageAccess()`][storage-access] can be used in supporting browsers to observe whether unpartitioned storage is available.

## Request header

If an alternate loading mode is used, the user agent will send a `Sec-Loading-Mode` request header indicating the mode. The server may respond with an error status code (400-599), in which case prefetching/prerendering will be considered to have failed, regardless of the response body.

A server could defer non-idempotent behavior such as impression counting,  or it could reject prerender requests altogether without needing to do the full work to generate a response (since it need only inspect the request headers).

> TODO: Should we also/instead send `Sec-Purpose`? Should `Sec-Fetch-Mode` differ?

## Risks

__Credentialed requests__ allow fetching the right resource for the user, but the web is increasingly moving toward a model whereby an origin cannot trigger credentialed requests to another user except as part of a committed action (i.e., a navigation). Forward-looking prerendering should prefer to use uncredentialed requests to reduce the risk of identifying the user when doing so is undesirable, and should also deny access to unpartitioned storage under those circumstances.

Requests originating from the same __source IP address__ or otherwise implicitly detectable as the same user (e.g. fingerprinting approaches) may sometimes allow identification of the user even when credentials like cookies are not available. Forward-looking prerendering should allow the user agent to mitigate these risks, for example by obscuring the source IP (with a proxy server or [CDN][ip-blindness] that does not disclose it to the origin server, or by taking advantage of network capabilities to use [multiple IP addresses][ipv6-privacy]) and by making less fingerprintable data available to content during prerendering, if possible.

If approaches which restrict access to credentials and storage are used, __existing content may be broken__ if prefetched or prerendered in this way. This could be mitigated by user agent heuristics to only load content believed to work correctly (e.g. via reporting from past visitors to that site or from a robot indexer) or by an author declaration whether the resource will function correctly with this modified behavior. This document proposes the latter.

Server behavior in response to a GET request __may not be idempotent__. Thus issuing a request early may lead to changes in server state, such as modifying data or recording an ad impression. Unauthenticated requests to servers on the public Internet are believed to be at somewhat lower risk, because the lack of credential likely does not convey significant authority to make destructive changes and because such servers already contend with web crawlers which issue such requests. In the same-origin case, an express signal from the author that the user agent should prerender is also an indication that the request is likely to be idempotent. An alternative future direction for exploration is a capability for an origin to declare that certain URLs can be accessed idempotently, for example by responding to OPTIONS requests or by serving a manifest from a well-known URL, but this suggests a higher barrier to entry.

There is a risk that loading the resource may be __resource-intensive__. This is largely out of scope of this document. User agents may cancel prerendering if it has become too resource-intensive and may apply a variety of heuristics to make an educated decision about whether prerendering is likely to be lightweight.

Finally, there is the risk that any proposal is __too arduous for adoption__. Unless the effect on author incentives is extremely strong it will be very difficult to convince them to deploy a complex solution. The simpler and easier to adopt, the more likely adoption will become widespread.

## Alternatives considered

### No declaration

Why is a declaration needed at all? Why can't the document be fetched and loaded normally, just without credentials?

The origin may already have data in its unpartitioned storage, but from the above, our goal is to provide for prerendering which does not grant access to it until the user actually navigates to the destination site. However, this may cause the content to load and behave differently than it would have with access to its unpartitioned storage. Then, when the prerendered document is preseneted, the user will observe any such differences as brokenness.

For example, an authenticated user or subscriber will observe that on navigation, that state is not reflected (they appear logged out or encounter a paywall). The user is likely to __blame the innocent destination site for this brokenness__. (Naturally, this is unlikely to be an issue if the origin has no existing cookies or other storage.)

The user agent could reload the page on navigation, but this would defeat the point of prerendering.

If the user agent could detect brokenness, it could avoid this. However, this seems impossible to do in general, because:
* the server response could depend on the presence of cookies and other credentials
* client-side access can be detected, but it is unclear how to infer whether this corresponds to user-visible brokenness

It might be possible for the user agent to augment author declarations with a list of origins or documents known to behave well, as a browser feature. This would depend on identifying such sites in a fairly reliable way and providing a mechanism for users to reload if they observe brokenness. However, such a mechanism would have limitations and would necessarily not behave the same in all browsers. The web platform should provide a way to more predictably get the desired behavior.

### Opt-out only

Could an opt-out suffice? It would seem to make it easier to increase coverage.

In principle, yes. However, this would mean that content may become broken (as described above) and require authors to roll out an opt-out to simply restore the previous level of functionality. This seems problematic, especially since we anticipate a large fraction of the web would be affected.

### HTTP header exchange only

An opt-in solely based on HTTP request and response headers is appealing. It allows the fetch to be terminated before processing the response body, and doesn't require HTML parsing or other complicated logic to handle.

The largest drawback here is one of adoption. In order to make as much content as possible available for uncredentialed prerendering, we would like to make it as easy as possible for authors to mark eligible content. We have heard from developers that many of them find it much easier to deploy changes that only affect content than changes which also require server behavior changes, even relatively straightforward ones. For example, these may be managed by different teams or not be possible at all. One key example here is that GitHub Pages doesn't allow users to set response headers.

This strongly indicates an opt-in in the HTML document, such as a `<meta>` tag, attribute of the `<html>` element, or other affordance entirely within the HTML response body.

### Document policy

[Document policy][document-policy] provides a related mechanism, which allows a document to provide a set of behavior changes and restrictions it wishes to apply to itself in an HTTP response header, `Document-Policy`. The request may contain a `Sec-Required-Document-Policy` header, which indicates the minimum level of strictness for each policy that is required -- otherwise the load will fail.

Document policy does not support a mechanism for setting policy inside the response body, which we believe to be important to ease of deployment by authors. It might be possible to extend document policy to also support this, but there would be significant added complexity in document policy, such as algorithms for combining policy declarations in both places and deferring loads in contexts with a required document policy until it can be determined that the merged policy is suitable. These problems are somewhat similar in the special case this proposal discusses than in the general case of document policy.

`Sec-Required-Document-Policy` would not replace the need for a [request header](#request-header), since this is settable by content that is not genuinely prerendering, e.g. via `<iframe policy>`.

Document policy also defines a strict mechanism for inheritance of strict document policy (always inherited by subframes, declaration is required or load fails), but this is not flexible enough for the preferred behavior above. In particular the option of deferral wouldn't ordinarily make sense for document policy (since required policy and policy both cannot change), but do make sense for prerendering, where the user may eventually navigate.

Document policy is also immutable, so either we would have to introduce a notion of mutable required policy and mutable policy, or we would have to define a policy named something like `initial-unpartitioned-storage` that doesn't change, but which only controls unpartitioned storage "initially". This is somewhat awkward and could lead to an explosion of "initial" vs "always" policies.

We do, however, intend to use common integration points with permissions policy such as the HTML [allowed to use][allowed-to-use] algorithm to minimize the collatoral complexity imposed on other specifications, where possible.

[allowed-to-use]: https://html.spec.whatwg.org/#allowed-to-use
[document-policy]: https://github.com/w3c/webappsec-permissions-policy/blob/master/document-policy-explainer.md
[http-structured-header]: https://httpwg.org/http-extensions/draft-ietf-httpbis-header-structure.html
[ip-blindness]: https://github.com/bslassey/ip-blindness
[ipv6-privacy]: https://tools.ietf.org/html/rfc4941
[storage-access]: https://github.com/privacycg/storage-access
