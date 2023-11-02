# Speculation rules

[Read the spec](https://wicg.github.io/nav-speculation/speculation-rules.html)

## Table of contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Background](#background)
- [Goals](#goals)
- [Non-goals](#non-goals)
- [The proposal](#the-proposal)
  - [List rules](#list-rules)
  - [Requirements](#requirements)
  - [Window name targeting hints](#window-name-targeting-hints)
  - [Explicit referrer policy](#explicit-referrer-policy)
  - [Document rules](#document-rules)
    - [Alternatives](#alternatives)
  - [Using the Document's base URL for external speculation rule sets](#using-the-documents-base-url-for-external-speculation-rule-sets)
  - [Content Security Policy](#content-security-policy)
  - [Eagerness](#eagerness)
  - [`No-Vary-Search` hint](#no-vary-search-hint)
- [Future extensions](#future-extensions)
  - [Handler URLs](#handler-urls)
  - [External speculation rules via script elements](#external-speculation-rules-via-script-elements)
  - [More speculation actions](#more-speculation-actions)
- [Proposed processing model](#proposed-processing-model)
- [Developer tooling](#developer-tooling)
- [Feature detection](#feature-detection)
- [Alternatives considered](#alternatives-considered)
  - [Extending the `<link>` element](#extending-the-link-element)
    - [General interop and compat concerns](#general-interop-and-compat-concerns)
    - [Forward-compatibility problems](#forward-compatibility-problems)
    - [Duplication](#duplication)
  - [Alternatives to `"target_hint"`](#alternatives-to-target_hint)
  - [Alternatives to `Speculation-Rules` header](#alternatives-to-speculation-rules-header)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Background

A web-facing "trigger" is a mechanism for web content to permit or encourage preloading (prefetching or prerendering) of certain URLs.

For example, a prerendering trigger conveys to the browser:

- the user is reasonably **likely to navigate** to the URL
- prerendering the URL is not believed to have undesirable **side effects**, at least under certain conditions
- the response body is expected to be **compatible** with prerendering (i.e., the browser probably won't need to abort the prerender due to some disallowed behavior)

The browser need not fully trust these assertions about cross-origin URLs (those relevant for security and privacy should be verified), but having them lets the browser focus on work likely to improve navigation performance.

The existence of web-facing triggers doesn't necessarily preclude the user agent from triggering preloading at other times, such as preloading a user's most frequently visited sites.

The [Resource Hints][resource-hints] specification defines a number of current triggers, a family of relations usable in a `<link>` element or `Link` response header. These are inconsistently implemented and do not serve all the desirable [goals](#goals). See more discussion in the [Alternatives considered](#alternatives-considered) section.

## Goals

Authors must currently **duplicate** the URLs they wish to prefetch: a `<link>` in the head of the document and an `<a>` in the body, or use script to synchronize these at runtime. Ideally, authors should be able to centrally declare which links are eligible for prefetching and prerendering without needing to rewrite the logic for emitting links into their document or write script to work around the issue.

The success of libraries like [Quicklink](https://getquick.link/) demonstrates that even relatively simple heuristics can bring significant improvements to navigation performance and engagement. The browser is well-positioned to efficiently provide these and improve them over time, but the current scheme leaves authors to **decide for themselves**, in part by not offering wildcard matching and similar tools to identify the links which can safely be fetched.

More sophisticated authors often have aggregate **analytics**, user history on their origin, search ranking signal, or other data which provides a useful signal *in combination with* heuristics that apply in general, like the viewport-based heuristic. For best results, the browser needs a way to accept this information to make the best prediction possible.

Some sites would like to prefetch outgoing links to untrusted third-party origins **without disclosing the user's client IP address**. Browsers which can achieve this, such as through the use of a virtual private network or [private prefetch proxy](https://github.com/buettner/private-prefetch-proxy) need to be told that prefetching is acceptable *only if this mechanism is employed*, and browsers that cannot achieve this (or where the user prefers not to use it) need to understand that prefetching should not occur.

Another anticipated direction of exploration is "template" or "handler" pages which can substantially prepare for a navigation to a number of **similar pages** (e.g., a blank product detail page on an e-commerce site), without knowing which product will ultimately be selected. This would allow common markup, script and other subresources to be ready.

Accordingly, we need a trigger that is flexible enough to accommodate these and other, unanticipated, future needs. It should also **fail safe**, meaning that if new complications are added in the future, it should default to *not* making requests which may not be intended, rather than failing open (e.g., erroneously issuing fetches due to having ignored unsupported syntax).

## Non-goals

While we intend to better specify the behavior of "prefetch", "prerender" and similar speculated actions, these specifications are largely separable from the trigger API itself. In fact, this specified behavior should be shared as much as possible between existing resource hints, those proposed in this document, and browser features for prefetching and prerendering.

This proposal doesn't aim to address concerns about any particular provider, service or software a browser may use to provide [IP anonymization](./anonymous-client-ip.md). Feedback on [private prefetch proxies](https://github.com/buettner/private-prefetch-proxy/issues) is welcome, but tracked separately.

## The proposal

This explainer proposes a new way for content to declare what kind of speculation the user agent may do about future user activity, especially outgoing navigation, in order to reduce user-visible latency. This speculation may have side effects, but an author's declaration that certain speculative activity is productive enables the user agent to speculate more often.

It is intended to be more general than existing resource hints for navigation, and allows the author to make even weak declarations about the likelihood that the navigation will occur. The user agent can combine this with its own heuristics to decide whether to speculate.

The rules are expressed as a JSON object included within a script tag (like [import maps][import-maps]). Currently, like import maps, script tags are only used for specifying speculation rules inline; [future extensions](#external-speculation-rules-via-script-elements) may allow a `src` attribute to load external rule sets.

The following example illustrates the basic idea:

```html
<script type="speculationrules">
{
  "prerender": [
    {"source": "list",
     "urls": ["/home", "/about"]}
  ],
  "prefetch": [
    {"source": "list",
     "urls": ["https://en.wikipedia.org/wiki/Hamster_racing"],
     "requires": ["anonymous-client-ip-when-cross-origin"]}
  ]
}
</script>
```

(The use of `<script>` is basically because only a few elements allow the HTML parser to enter RCDATA mode, and `<script>` has already been used in this way. This doesn't necessarily mean that these rules should respect the `script-src` CSP directive.)

For use cases where it is preferable to provide speculation rule sets without modifying a document, we introduce the `Speculation-Rules` HTTP header. The header's values are URLs to external resources containing speculation rule sets. The rules are expressed in the same JSON object format as the inline case. The MIME type of the resource must be `application/speculationrules+json`.

For example, suppose a rule set is available at `https://example.com/speculation-rules.json`. The response headers for a request for `https://example.com/` could include:
```
Speculation-Rules: "speculation-rules.json"
```

The rules are divided into sections by the action, such as `"dns-prefetch"`, `"preconnect"`, `"prefetch"`, `"prefetch_with_subresources"`, or `"prerender"`, that they authorize. A user agent may always choose to stop early, for instance by prefetching where prerendering was permitted. Currently we have only specified `"prefetch"` and `"prerender"`, but we want to keep the other possibilities in mind for the future.

Since these are rules for optional behavior (the UA is always free not to speculate), parsing of these can be somewhat conservative. If a UA sees a rule it does not understand, that rule is discarded. Because a rule always authorizes additional speculation (but does not confine speculation allowed by other rules), discarding rules never authorizes more speculation than the author intended, only less.

The rules are divided into a number of simple pieces that build on one another, and could be shipped largely independently, due to the conservative parsing strategy.

### List rules

Currently, the only type of rule specified is a _list_ rule, denoted by `"source": "list"`. A list rule has an express list of the _URLs_ to which the rule applies. The list can contain any URLs, even ones for which no link or other reference to the URL exists in the document. This is especially useful in cases where the expected navigation corresponds to a link that will be added dynamically, or to an anticipated script-initiated navigation.

These URLs will be parsed relative to the document base URL (if inline in a document) or relative to the external resource URL (if externally fetched).

### Requirements

A rule may include a list of _requirements_, which are assertions in the rule about the capabilities of the user agent while executing them.

Currently the only requirement that is specified is denoted by `"anonymous-client-ip-when-cross-origin"`, which we only support on `"prefetch"` rules. If present, it means that the rule matches only if the user agent can [prevent the client IP address from being visible to the origin server](./anonymous-client-ip.md) if a cross-origin prefetch request is issued. An example usage is as follows, wherein a news aggregator site is asking to prefetch the first four links, but only if doing so does not leak the user's IP:

```json
{"prefetch": [
  {"source": "list",
   "urls": [
    "/item?id=32480009",
    "https://support.signal.org/hc/en-us/articles/4850133017242",
    "https://discord.com/blog/how-discord-supercharges-network-disks-for-extreme-low-latency",
    "https://github.com/containers/krunvm"
   ],
   "requires": ["anonymous-client-ip-when-cross-origin"]}
]}
```

We require that user agents discard any rules with requirements that are not recognized or supported in the current configuration, so this system fails closed. Additionally, due to the conservative parsing rules, any UA which did not support requirements at all would discard all rules with requirements.

### Window name targeting hints

For implementation reasons, it can be difficult for user agents to prerender content without knowing which window it will end up in. For example, the browser might prerender content assuming that it will be activated in the current window, replacing the current content, but then the user might end up clicking on an `<a href="page.html" target="_blank">` link, so the prerendered content is wasted.

To help with this, `"prerender"` rules can have a `"target_hint"` field, which contains a [valid browsing context name or keyword](https://html.spec.whatwg.org/#valid-browsing-context-name-or-keyword) indicating where the page expects the prerendered content to be activated. (The name "target" comes from the HTML `target=""` attribute on hyperlinks.)

```html
<script type=speculationrules>
{
  "prerender": [{
    "source": "list",
    "target_hint": "_blank",
    "urls": ["page.html"]
  }]
}
</script>
<a target="_blank" href="page.html">click me</a>
```

This is just a hint, and is not binding on the implementation. Indeed, we hope that it one day becomes unnecessary, and all implementations can activate prerendered content into any target window. At that point, the field can be safely ignored, and removed from the specification. But at least for Chromium, getting to that point might take a year or so of engineering effort, so in the meantime `"target_hint"` gives developers a way to use prerendering in combination with new windows.

Note that if a page is truly unsure whether a given URL will be prerendered into the current window or a new one, they could include prerendering rules for multiple target windows:

```json
{
  "prerender": [
   {"source": "list",
    "target_hint": "_self",
    "urls": ["page.html"]
   },
   {"source": "list",
    "target_hint": "_blank",
    "urls": ["page.html"]
   }]
}
```

However, in implementations such as Chromium that need the target hint, this will prerender the page twice, and thus use twice as many resources. So this is best avoided if possible.

### Explicit referrer policy

By default, the referring document's referrer policy is used for the speculative request. The policy to use for the speculative request can be specified in a rule using the `"referrer_policy"` key and the desired referrer policy string.

For example:
```json
{
  "prefetch": [
    {"source": "list",
     "urls": ["https://en.wikipedia.org/wiki/Lethe"],
     "referrer_policy": "no-referrer"
    }
  ]
}
```

For speculation actions that would be prevented by the [**sufficiently-strict referrer policy** requirement](./fetch.md#stripping-referrer-information) on a referring page with a lax policy, this allows the referring page to set a stricter policy specifically for the speculative request.

Note that referrer policy matching is not done between the speculative request and the user facing navigation. So given the above rule, a request would be made with `no-referrer` and would still be used even if the user clicked on:
```html
<a href="https://en.wikipedia.org/wiki/Lethe" referrerpolicy="unsafe-url">
```

### Document rules

In addition to list rules, we envision _document_ rules, denoted by `"source": "document"`. These allow the user agent to find URLs for speculation from link elements in the page. They may include criteria which restrict which of these links can be used.

The URL can be compared against [URL patterns][urlpattern] (parsed relative to the same base URL as URLs in list rules).

<dl>
<dt><code>"href_matches": ...</code></dt>
<dd>requires that the link URL match the provided pattern (or any of the provided patterns, if there are multiple)</dd>
</dl>

The link element itself can also be [matched][selector-match] using [CSS selectors][selectors].

<dl>
<dt><code>"selector_matches": ...</code></dt>
<dd>requires that the link element match the provided selector (or any of the provided selectors, if there are multiple)</dd>
</dl>

Any of these simple conditions can be negated and combined with conjunction and disjunction.

<dl>
<dt><code>"not": {...}</code></dt>
<dd>requires that the condition not match</dd>
<dt><code>"and": [...]</code></dt>
<dd>requires that every condition in the list match</dd>
<dt><code>"or": [...]</code></dt>
<dd>requires that at least one condition in the list match</dd>
</dl>

An example of using these would be the following, which marks up as safe-to-prerender all same-origin pages except those known to be problematic:

```json
{
  "prerender": [
    {"source": "document",
     "where": {"and": [
       {"href_matches": "/*\\?*"},
       {"not": {"href_matches": "/logout\\?*"}},
       {"not": {"selector_matches": ".no-prerender"}}
     ]}}
  ]
}
```

#### Alternatives

There are a number of alternatives to this that were not selected, such as:

* **Implicit `"and"` on conditions.** A straw poll suggested this wasn't obvious, and making this explicit made it easier to understand.
* **A bespoke parsed expression syntax.** This has nice ergonomic properties for complex expressions, but expressions are expected to be fairly simple in practice. If strings like selectors and URL patterns might be controlled by an attacker, this would also potentially introduce injection vulnerabilities (along the lines of XSS and SQL injection), unless an even more cumbersome syntax (along the lines of prepared statements) were used. This would also generally be more difficult to programmatically manipulate, whereas keeping this in pure JSON allows existing JSON tooling in various languages (but most notably JavaScript and web browsers) to be manipulate it.
* **Combining negation with conditions.** Given the desire to provide more general logic primitives, this would be somewhat surprising. Negation with a separate object is longer but not dramatically longer. In the case of CSS selectors, a shorter syntax for negation is already available even without support at this level (namely, the `:not(...)` pseudo-class).

### Using the Document's base URL for external speculation rule sets

For rule sets that are externally fetched, urls in list rules and url patterns in document rules are parsed relative to the external resource's url. To parse urls in a list rule relative to the document's base url, `"relative_to": "document"` could be specified as part of the speculation rule:

```json
{
  "source": "list",
  "urls": ["/home", "/about"],
  "relative_to": "document"
}
```

For document rules, `"relative_to"` can be paired directly with `"href_matches"` and the document's base url would only be used for patterns in that particular predicate:

```json
{
  "source": "document",
  "where": {"or": [
    {"href_matches": "/home\\?*", "relative_to": "document"},
    {"href_matches": "/about\\?*"}
  ]}
}
```

(In the above example, only the first `href_matches` would use the document's base URL.)

### Content Security Policy

Speculation rules can be embedded inline within a `script` tag with `type="speculationrules"`, and restricted by the `script-src` and `script-src-elem` CSP directive. To allow inline speculation rules, use either the `'inline-speculation-rules'` or `'unsafe-inline'` keyword. Using `script-src 'inline-speculation-rules'` or `script-src-elem 'inline-speculation-rules'` helps developers to permit inline speculation rules but still disallow unsafe inline JavaScript.

The `default-src` directive can be used to restrict which URLs can be prefetched or prerendered.

### Eagerness

Developers may provide hints about how eagerly the browser should preload links in order to balance the performance advantage against resource overhead.
This field accepts one of the strings `"conservative"`, `"moderate"`, `"eager"`, and `"immediate"` as the value, and it is applicable to both `"prefetch"` and `"prerender"` actions and both `"list"` or `"document"` sources.
If not specified, list rules default to `"immediate"` and document rules default to `"conservative"`.
The user agent takes this into consideration along with its own heuristics, so it may select a link that the author has indicated as less eager than another, if the less eager candidate is considered a better choice.

```json
{
  "prefetch": [
    {"source": "list",
     "urls": [
       "https://en.wikipedia.org/wiki/Lethe",
       "https://github.com/containers/krunvm"
     ],
     "eagerness": "eager"
    }
  ],
  "prerender": [
    {"source": "document",
     "where": {"and": [
       {"href_matches": "/*\\?*"},
       {"not": {"href_matches": "/logout\\?*"}},
       {"not": {"selector_matches": ".no-prerender"}}
     ]},
     "eagerness": "conservative"
    }
  ]
}
```

### `No-Vary-Search` hint

We would like preloading to make use of the improved matching enabled by the [`No-Vary-Search`](./no-vary-search.md) HTTP response header. When the user agent gets the response to a preloading request, it can make use of the `No-Vary-Search`, if present, when deciding whether to serve a subsequent navigation with the preload. However, if there is an ongoing preloading request for which the user agent has not yet received the response headers, we would need to make a tradeoff. Consider this page:

```html
<script type="speculationrules">
{
  "prefetch": [{
    "source": "list",
    "urls": ["/products"]
  }]
}
</script>
<a href="/products?id=123">Product ABC</a>
```

Consider what happens if the user starts a navigation to `/products?id=123` when the headers for the prefetch of `/products` have not been received yet. We have two cases:

1. `/products` _has_ `No-Vary-Search: params=("id")`. For example, `/products?id=123` means to render the products view, and use client-side script to highlight the `X`th product. Then, our prefetch could be usable.
1. `/products` _does not_ have `No-Vary-Search: params=("id")`. For example, `/products` is an index listing all the products, whereas `/products?id=123` is a specific product page. Then, our prefetch was wasted, and we need to go fetch the separate `/products?id=123` page.

Should we wait for the prefetch of `/products` to finish? This makes case (1) better and case (2) worse. Or do we start a concurrent fetch to `/products?id=123`? This makes case (1) worse and case (2) better.

Furthermore, for prefetches triggered by the user agent's heuristics, not knowing the `No-Vary-Search` value creates an additional tradeoff of whether to perform the prefetch. Consider the following:

```html
<script type="speculationrules">
{
  "prefetch": [{
    "source": "list",
    "urls": ["/products"],
    "eagerness": "conservative"
  }]
}
</script>
<a href="/products?id=123">Product ABC</a>
```

Here, the conservative [eagerness](#eagerness) value indicates that the browser _may_ prefetch the given URL, and not that it _should_ prefetch the given URL. So, the browser probably won't prefetch `/products` on page load. But, let's say the user presses down on the link. Now it seems pretty likely that `/products?id=123` is going to be visited, so it might be a good time to prefetch `/products`. After all, `/products` might come back with `No-Vary-Search` indicating that the `id` query parameter is unimportant. If we're in case (1) as described above, then the prefetch is valuable. If we're in case (2), then prefetching is wasteful.

To solve this, we have the speculation rules syntax provide a hint for what the author expects the `No-Vary-Search` value to be. A rule may have an `"expects_no_vary_search"` field which has the expected [header value](./no-vary-search.md#the-header) as a string.

```html
<script type="speculationrules">
{
  "prefetch": [{
    "source": "list",
    "urls": ["/products"],
    "expects_no_vary_search": "params=(\"id\")"
  }]
}
</script>
<a href="/products?id=123">Product ABC</a>
```

With this, the author indicates that case (1) described above is what the server is expected to produce. If a navigation starts while there is an ongoing prefetch of `/products`, this informs the user agent that it is appropriate to wait for the prefetch, instead of immediately starting another fetch. Furthermore, in the non-eager version, this informs the user agent's heuristics that prefetching `/products` is an appropriate thing to do when it is likely that there will be a navigation to `/products?id=123`.

We expect the typical use case for this will involve the author copying the header value verbatim into the `expects_no_vary_search` field, so we use a string representation of the [structured header value](./no-vary-search.md#the-header), instead of creating a second representation based on JSON structures.

Nevertheless, it is not necessary for the actual `No-Vary-Search` header value in the response to match the expected value exactly. In the above example, suppose the rule still only specifies `"params=(\"id\")"`, but the server actually responded with `No-Vary-Search: key-order, params=("id" "something_else")`. `/products` and `/products?id=123` are equivalent given the `expects_no_vary_search` and are still equivalent given this more flexible header value, so the prefetch can still be used. However, if the hint is incorrect such that two URLs are equivalent given the hint, but not equivalent given the header value, then the prefetch cannot be used. The consequence of incorrect hints is the wasteful behaviour described above. For example, in case (2) above, suppose we provide the hint of `"params=(\"id\")"`, but the server does not include a `No-Vary-Search` value. Then the prefetch is wasted and a navigation may have pointlessly blocked on the prefetch response.

## Future extensions

### Handler URLs

Another possible future extension, which would likely need to be restricted to same-origin URLs, could allow the actual URL to be preloaded to be different from the navigation URL (but on the same origin), until the navigation actually occurs. This could allow multiple possible destinations with a common "template" (e.g., product detail pages) to preload just the template. This preloaded page could then be used regardless of which product the user selects.

```json
{"prerender": [
  {"source": "document",
   "if_href_matches": ["/details/([a-z0-9-]+)"],
   "handler": "/details/_prerender"}
]}
```

### External speculation rules via script elements

Like import maps, `<script>` elements can currently only load speculation rules inline, with the speculation rules JSON being contained in the `<script>` element's child text content. However, [like import maps](https://github.com/WICG/import-maps/issues/235), it would be convenient for authors if we allowed `<script type="speculationrules">` to instead have an `src=""` attribute pointing to an external URL.

The requirements for external rule sets loaded via the `Speculation-Rules` header would also apply here, such as the use of the `application/speculationrules+json` MIME type.

Some questions to answer here include the interaction with CSP. The answers might not necessarily be the same for import maps and speculation rules, since import maps give a more direct ability to interfere with script execution.

### More speculation actions

As mentioned previously, we have currently only specified `"prefetch"` and `"prerender"` speculation actions.

Adding `"dns-prefetch"` and `"preconnect"`, to mirror [Resource Hints](https://w3c.github.io/resource-hints/), would be an obvious extension, simply giving a more-ergonomic and capable way of triggering those actions.

Another envisioned speculative action is `"prefetch_with_subresources"`, which prefetches a document and then uses the HTML preload scanner to find other subresources that are worth preloading. Chromium currently does something similar (known as "[NoState Prefetch](https://developer.chrome.com/blog/nostate-prefetch/)") for `<link rel="prerender">`. But, we're not yet sure this feature is pulling its weight, in between the lightweight prefetch and the fully-instant prerender features, so it's not yet clear whether this will be worth integrating.

## Proposed processing model

Conceptually, the user agent may from time to time execute a task to consider speculation. (In practice, it will likely do this only in response to some sort of DOM mutation or other event that indicates the applicable rules have changed, and may limit its attention to the affected parts of the document.) Changes to the DOM that are undone within a task cannot therefore be observed by this algorithm.

To consider speculation is to look at the computed ruleset for the document (merging, if there are multiple), gather a list of candidate URLs, combine the author-declared likelihood with its own heuristics (which may include device or network characteristics, page structure, the viewport, the location of the cursor, past activity on the page, etc.), and thus select a subset of the allowed actions to execute speculatively.

The user agent may schedule the fetch of external speculation rules at its discretion. For example, the user agent could defer the fetching of speculation rules in order to prioritize render-blocking resources. The user agent could therefore also choose not to fetch an external speculation rule set at all. For example, if the user agent does not intend to speculate, there is no need to fetch speculation rule sets. Furthermore, the user agent may consider speculation without needing to have fetched all external speculation rule sets specified for the document. For example, if a document has inline speculation rules and an external rule set that the user agent has not yet fetched, the user agent is free to consider speculation based just on the inline rule set.

At any time the user agent may decide to abort any speculation it has started, but it is never required to do so. However, if at the time of considering speculation a speculation would no longer be permitted (e.g., because the rules changed, the initiating element was modified, the document base URL changed, or another part of the document changed such that selectors no longer match), the user agent should abort the speculation if possible.

## Developer tooling

It will likely be useful to surface in developer tools what rules and URLs have been found, and what the heuristic probability used for each was. Developer tools should also provide an option to force the user agent to execute a speculation that it may have deemed low probability, so that the developer can reproducibly observe behavior in this case.

This information and control is important because otherwise it may be difficult to validate correct behavior as it would otherwise depend on heuristics unknown to the author. Similarly testing tools such as [WebDriver][webdriver] should likely permit overriding the user agent's selection of which valid speculations to execute.

## Feature detection

If the browser supports [`HTMLScriptElement`](https://html.spec.whatwg.org/multipage/scripting.html#htmlscriptelement)'s [`supports(type)`](https://html.spec.whatwg.org/multipage/scripting.html#dom-script-supports) static method, `HTMLScriptElement.supports('speculationrules')` will return true.

```js
if (HTMLScriptElement.supports && HTMLScriptElement.supports('speculationrules')) {
  console.log('Your browser supports speculationrules.');
}
```

## Alternatives considered

### Extending the `<link>` element

The obvious alternative is to extend the `<link>` element. Let's discuss why that's undesirable.

#### General interop and compat concerns

The existing `<link rel="prefetch">` and `<link rel="prerender">` link relations are not consistently implemented, or well specified. They do different things in different browsers, and in some cases even have magical behavior for `as="document"` (navigational preloading) vs. other `as=""` values (subresource preloading).

Current implementations are also not necessarily compatible with [storage partitioning](https://github.com/privacycg/storage-partitioning/), as they were designed before such efforts. So there may need to be future backward-incompatible changes to them to meet browser teams' new goals around privacy.

As such, it's much nicer if we can start from a clean slate with a new trigger, which does not have any preexisting implementations which could be hard to change the semantics of. We do want to eventually get interop on these; our current best guess for how this will turn out is that `<link rel="prefetch">` [will become about subresource prefetching only](https://github.com/whatwg/html/pull/8111), and `<link rel="prerender">` (which is Chromium-only) will be removed.

#### Forward-compatibility problems

`<link>` does not lend itself well to adding requirements, of the type we [have included](#requirements) in speculation rules. For example, if we tried to add support for requiring an anonymous client IP, doing so in the naive way would accidentally cause existing browsers to ignore the requirement:

```html
<!-- existing browsers would prefetch this directly -->
<link rel="prefetch" href="https://example.org/" mustanonymize>
```

The only real workaround for this is to invent a new `rel=""` value which has different behavior, e.g., pays attention to a new `requirements=""` attribute.

#### Duplication

As mentioned in [the Goals section](#goals), `<link>` also doesn't lend itself to reducing duplication with anchors already in the document, requiring the author to either statically insert the full set of links into the document resource (and since they appear in the `<head>`, this implies buffering) or dynamically synchronize the links in the page with `<link>` references in the head, potentially updating them as script mutates the document.

With [document rules](#document-rules), we can do much better.

### Alternatives to `"target_hint"`

One alternative to the explicit [`"target_hint"`](#window-name-targeting-hints) field is for implementations such as Chromium, which need to know the target window before prerendering, to use heuristics to try to figure out the target window. For example, given a prerender rule targeting a given URL, they could scan for links to that URL in the current DOM, and use that link's `target=""` to guess at the target window.

This has a few disadvantages:

- It doesn't work for certain navigations:
  - Those triggered via JavaScript, e.g. `<button onclick="window.open(url)">`.
  - Those triggered via links that are not yet in the DOM at the time the prerendering occurs, e.g. those due to clicking inside a pop-up which is inserted dynamically.
- It is slightly more costly for performance, requiring a scan of the entire DOM whenever speculation rules are updated.

We worry that such a technique might encourage developers to insert hidden fake links into the DOM to trigger the heuristic.

### Alternatives to `Speculation-Rules` header

There is an existing header, [`Link`][link-header], which also allows for loading resources through headers. To use this, we would introduce a new [link type][link-type], "`speculationrules`". The header is semantically equivalent to the HTML `<link>` element, so using this header would mean we would have to support speculation rules loading with a `<link>` element as well. This seems sensible, especially given that web developers would already be familiar with loading declarative content with `<link>` elements (e.g. style sheets). However, this has a number of drawbacks:
1. For new kinds of resources to fetch, we want to require CORS. The `<link>` element has an unsuitable default in the form of the `crossorigin` attribute.
2. There are a number of other attributes which are undesirable or irrelevant for speculation rules (e.g. `type`).
3. The `rel` attribute can actually have multiple values, so this may lead to confusing combinations (e.g. `rel="prefetch speculationrules"`).
4. Since we already use `<script>` elements for inline speculation rules, it would be appropriate to support external speculation rules with `<script src="...">`, as noted [above](#external-speculation-rules-via-script-elements), but then we would have two ways of doing the same thing which could negatively impact developer experience.

A number of these issues are minor and/or have been handled by other features. For example, the `"manifest"` link type requires CORS and uses a different interpretation of the `crossorigin` attribute. However, the concern around multiple tags which implement the same behaviour of loading external speculation rule sets is more significant. If we were to try to avoid this by not introducing `<script src="...">` and exclusively using `<link>` for the external case, this would lead to a confusing inline vs. external element difference, similar to the case of `<style>` elements.

Another alternative would be to introduce a `Script` header, given that we’re using the `<script>` element for inline speculation rules. However, at this stage we’d only be proposing the header for usage with declarative content, and not active script execution. This seems counterintuitive. The `Script` header would not be used to implement the very thing its name implies. At this point, there does not appear to be an appetite for script execution via headers. Supposing there were, we’d need to consider a number of issues with that design. Due to the risks associated with script execution, this would require especially careful security consideration. Script execution via headers would also likely be awkward to feature detect. In order to check whether a header based script ran, the author would presumably need to have a `<script>` element to run a script to check if the former script ran. This seems like it would defeat the purpose of the header mechanism. See also [this discussion](https://github.com/whatwg/html/issues/8321) related to the `Script` header which was unfavorable.

[import-maps]: https://github.com/WICG/import-maps
[link-header]: https://html.spec.whatwg.org/multipage/semantics.html#processing-link-headers
[link-type]: https://html.spec.whatwg.org/multipage/links.html#linkTypes
[resource-hints]: https://github.com/w3c/resource-hints
[selector-match]: https://drafts.csswg.org/selectors-4/#match-a-selector-against-an-element
[selectors]: https://drafts.csswg.org/selectors/
[urlpattern]: https://urlpattern.spec.whatwg.org/
[webdriver]: https://github.com/w3c/webdriver
