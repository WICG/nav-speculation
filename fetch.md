# Prerendering fetching modes

## Related issues and discussion

There is a long history of standards and implementation discussion around some of the problems that parts of
this document aim to bring clarity to, namely, the fetching of speculative resources intended to be used by
future navigations:
 - [w3c/resource-hints: Specify processing model in terms of Fetch](https://github.com/w3c/resource-hints/issues/86)
 - [w3c/resource-hints: Specify prerender processing model](https://github.com/w3c/resource-hints/issues/63)
 - [whatwg/fetch: Speculative Request Flag](https://github.com/whatwg/fetch/pull/881)
 - [whatwg/html: Add prefetch processing model & double-key cache protections](https://github.com/whatwg/html/pull/4115)

The above discussion revolves largely around `<link rel=prefetch>`, however our interest in standardizing and
implementing prerendering and portals demands the specification of properties shared by all speculative navigation
requests. These requests have the following properties:
 - Fetched with a speculative [network partition key][2], thus storing the resources in an isolated
   HTTP cache partition reserved for speculative navigation requests associated with a given origin
 - Fetched without credentials, as to preserve the user's privacy
 - Fetched with a limited amount of referrer information, as to preserve the user's privacy

In the rest of this document we go into more detail into the above restrictions. We also describe how these
restrictions interact with a [prerendering browsing context][4] once it is activated after navigation.

<details>
<summary>Prefetch-specific restrictions</summary>

In addition to the above restrictions, `<link rel=prefetch>` requests will have the following qualities:
 - The UA can opt to not fetch the request given implementation-defined constraints
   (commonly network speed, memory, etc.)
 - The request is fetched with a low implementation-defined [priority][5]
</details>

## HTTP cache partitioning

For privacy reasons, speculative navigation requests require the ability to fetch a resource while having
no side effects on HTTP cache partitions observable to any other pages. For example, if `a.com` prerenders
`b.com` and `b.com` fetches a bunch of subresources or has any number of nested browsing contexts, we need
some container to hold both the top-level resource and all subresources under it so that the fetching of
these resources is not observable to any non-speculative pages.

The Fetch Standard computes a [network partition key][2] in the [determine the http cache partition][0]
algorithm which is used to identify an HTTP cache partition. The key's primary identifier is the
[top-level origin][1] of the request's client (e.g., a `Window` object). For the privacy reasons mentioned
above, we cannot consult the cache partition that would typically be identified by a speculative navigation
request's [top-level origin][1]. Concretely, this can be achieved by adding an extra bit to the request's
computed [network partition key][2], signifying that the key specifically pertains to an isolated HTTP cache
partition associated with the top-level origin in the key. As mentioned before, all of the below resources will
need to utilize this cache key:
 - Top-level speculative resources
 - Subresources under top-level speculative resources
 - Nested browsing contexts and their subresources

### Cache partitioning after activation

At the point of activation, the various speculative HTTP cache partitions may contain resources that are now
safe to expose to the "typical" cache partitions that non-speculative pages use, since the user has clearly
expressed their intent to navigate. We can provide an optional step that merges all of the speculative
HTTP cache partitions with their non-speculative counterparts. In practice, this is pretty tricky and it is
expected that most implementations will not do this.

> TODO: There was discussion about doing this, but now I have reservations about even making this optional,
since all resources in the speculative partition will be the result of credential-less fetches, which might
not be useful to reference from this point on? This could use some more thought.

>TODO: It's more likely that an implementation will merge cookies so I should probably figure out how
that will work spec-wise.

### Alternatives considered

#### Using an out-of-band ephemeral cache

One alternative to using a speculative HTTP cache partition in the way described above is to use some
new of out-of-band ephemeral cache to hold these resources, and potentially discard them after activation.
In theory this approach is reasonable and solves the problem at hand, however the practical implications
in both spec and implementation of creating a new type of cache bring about a large amount of complexity
for an unclear benefit. Specifically, some of the problems that would need to be solved are:

 - Determining where this cache is layered with respect to the HTTP cache, and some already-existing
   in-memory caches such as the "list of available images"
 - Determining a reasonable set of cache read/write semantics
 - Exploring how this relates to the non-yet-spec'ed Memory Cache and Preload Cache
 - Potentially creating partitioning mechanics similar to those of the HTTP cache, for user privacy

While this alone is difficult, it also would be challenging to foster interoperability with the
usage of this brand new cache, particularly because:
 1. Many interactions with the cache may not be observable
 1. The few observable effects would be subtle
 1. Implementation-defined constraints around fetching speculative resources could lead to these resources
    non-deterministically not being fetched, making it difficult to test the cache

##### Ephepermal cache after activation

All requests originating from a [prerendering browsing context][4] after activation would stop targeting the
ephemeral resource cache, and use their "typical" HTTP cache partition.

Like the main proposal, we could potentially provide an optional cache merging step in which resources stored
in the ephemeral cache could be transferred to the HTTP cache for a more-permanent lifetime. This is not without
its own difficulties and complexities as previously described.

#### Bypassing the HTTP cache entirely

Another approach to this problem would be to force-send all requests that were initiated even indirectly
by a [prerendering browsing context][4] with the [cache mode][3] value of `"no-store"`. Fetching would behave
as though HTTP cache were not present, and it would be impossible to contaminate any HTTP cache partitions observable
to other pages.

The main downside of this approach is that we lose the ability to use any of the resources fetched by
the [prerendering browsing context][4] after activation. That is, we lose whatever benefits we could
gain by having the ability to merge speculative <=> "typical" HTTP cache partitions, should we decide
to go that route.

On a similar note, this approach does not integrate with `<link rel=prefetch>`, as the whole point is
to cache a top-level resource somewhere it can be usefully retrieved upon navigation. This means we're likely going to have
to spec and implement the HTTP cache partitioning mechanics described above anyways, so it is sensible for
other speculative navigation requests to piggy-back off of the same infrastructure.

Another possible complexity is that if we spec prerendering in a way such that [prerendering browsing contexts][4]
can be thrown away under implementation-defined constraints at any time, then we lose the ability to ever profit
from the prerendering work we've done. No resources in the [prerendering browsing contexts][4] are preserved
elsewhere, so it would be impossible to downgrade prerendering activation to something like prefetch activation.

> TODO(domfarolino): Clarify that the above is only considering the downgrading of prerender *activations*. There is
another kind of downgrade that we may want to consider, which is the scenario where under implementation-defined
constraints, the UA opts not to create a [prerendering browsing context][4], but instead downgrade the whole prerender
process to a simple prefetch. None of this is set in stone though.

## Fetching with no credentials

Speculative navigation requests should in no way leak the user's identity to third-party origins. A consequence of
this is that we must fetch all requests originating from a [prerendering browsing context][4] with no credentials.
As with the HTTP cache partitioning restrictions, this must apply to all of the following:
 - Top-level speculative resources
 - Subresources under top-level speculative resources
 - Nested browsing contexts and their subresources

Concretely this can be done by overriding the [credentials mode][6] of all requests coming from a
[prerendering browsing context][4] to the `"omit"` value.

### Credentials after activation

After a [prerendering browsing context][4] is activated, requests originating from it would no longer have
their credentials mode overridden, and would be fetched with whatever credentials were present in the user
agent's cookie store as is typical on the web platform.

> TODO: Discuss the possibility of partitioning the user agent's cookie store. In this proposal, the user
agent effectively ignores cookies that it already has, for requests initiated from a
[prerendering browsing context][4]. One downside of this proposal is that new credentials set on resources
in a [prerendering browsing context][4] will entirely be ignored. If the user agent's cookie store was
partitioned in a way similar to the HTTP cache, we could use an isolated speculative cookie store for all
requests in a given [prerendering browsing context][4], and optionally merge cookies in some fashion after
activation.

## Stripping referrer information

To preserve the user's privacy, there should be a limited amount of referrer information sent along with
speculative navigation requests. Given the sensitive nature of these requests, we believe it should not
be possible to expose the full referrer path when these requests are cross-origin. Instead, the total referrer
information will be limited to at most the referrer's origin. If a developer supplies the `referrerpolicy`
attribute on e.g., a `<link rel=prerender>` it should only be used for tightening the referrer policy beyond
the platform [default][7] of `strict-origin-when-cross-origin`. We can achieve this by defining a list of
a list of __sufficiently-strict referrer policies__ that are allowed for these requests.

As mentioned, the list of sufficiently-strict referrer policies are the policies that are as or more
strict compared to the platform [default][7] of `strict-origin-when-cross-origin`, which includes the
following policies:
 - `strict-origin-when-cross-origin`
 - `same-origin`
 - `strict-origin`
 - `no-referrer`

A speculative navigation request supplied with a referrer policy outside of this list will be silently
cancelled.

> TODO: We can also consider dispatching a console warning or firing the element's error event in these
cases to let developers know that the request was not able to be dispatched.

Furthermore, since the activation of a speculative navigation request keys on the referrer policy, we
guarantee that there is never a discrepancy between the referrer sent with the request, and the value
of `document.referrer` on the prerender page that may eventually get activated and promoted to using
first-party storage. For an example of this, see [this issue & comment][8].

### Referrer information after activation

This proposal applies the referrer redaction described above only to top-level speculative navigation
requests. For example, we don't override the referrer policy that would otherwise be set on the top-level
document in [prerendering browsing contexts][4], because any referrer information exposed from that document
does not expose any information about the page initiated the prerender. The most that a prerendered page
could expose about the referrer page is the value of its `document.referrer`, which is subject to the referrer
redaction described earlier in this section.

## Using a privacy-preserving proxy

> TODO: Touch on the possibility of establishing a connection from a different client IP address (e.g., using a
proxy server or virtual private network, if available)

[0]: https://fetch.spec.whatwg.org/#determine-the-http-cache-partition
[1]: https://html.spec.whatwg.org/multipage/webappapis.html#concept-environment-top-level-origin
[2]: https://fetch.spec.whatwg.org/#network-partition-key
[3]: https://fetch.spec.whatwg.org/#concept-request-cache-mode
[4]: https://htmlpreview.github.io/?https://raw.githubusercontent.com/jeremyroman/alternate-loading-modes/spec/index.html#prerendering-browsing-context
[5]: https://fetch.spec.whatwg.org/#concept-request-priority
[6]: https://fetch.spec.whatwg.org/#concept-request-credentials-mode
[7]: https://w3c.github.io/webappsec-referrer-policy/#default-referrer-policy
[8]: https://github.com/jeremyroman/alternate-loading-modes/issues/18#issuecomment-759703856
