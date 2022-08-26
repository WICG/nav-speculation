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
- [Future extensions](#future-extensions)
  - [Scores](#scores)
  - [Document rules](#document-rules)
  - [Handler URLs](#handler-urls)
  - [External speculation rules](#external-speculation-rules)
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

The success of libraries like [Quicklink](https://getquick.link/) demonstrates that even relatively simple heuristics can bring significant improvements to navigation preformance and engagement. The browser is well-positioned to efficiently provide these and improve them over time, but the current scheme leaves authors to **decide for themselves**, in part by not offering wildcard matching and similar tools to identify the links which can safely be fetched.

More sophisticated authors often have aggregate **analytics**, user history on their origin, search ranking signal, or other data which provides a useful signal *in combination with* heuristics that apply in general, like the viewport-based heuristic. For best results, the browser needs a way to accept this information to make the best prediction possible.

Some sites would like to prefetch outgoing links to untrusted third-party origins **without disclosing the user's client IP address**. Browsers which can achieve this, such as through the use of a virtual private network or [private prefetch proxy](https://github.com/buettner/private-prefetch-proxy) need to be told that prefetching is acceptable *only if this mechanism is employed*, and browsers that cannot achieve this (or where the user prefers not to use it) need to understand that prefetching should not occur.

Another anticipated direction of exploration is "template" or "handler" pages which can substantially prepare for a navigation to a number of **similar pages** (e.g., a blank product detail page on an e-commerce site), without knowing which product will ultimately be selected. This would allow common markup, script and other subresources to be ready.

Accordingly, we need a trigger that is flexible enough to accommodate these and other, unanticipated, future needs. It should also **fail safe**, meaning that if new complications are added in the future, it should default to *not* making requests which may not be intended, rather thaan failing open (e.g., erroneously issuing fetches due to having ignored unsupported syntax).

## Non-goals

While we intend to better specify the behavior of "prefetch", "prerender" and similar speculated actions, these specifications are largely separable from the trigger API itself. In fact, this specified behavior should be shared as much as possible between existing resource hints, those proposed in this document, and browser features for prefetching and prerendering.

This proposal doesn't aim to address concerns about any particular provider, service or software a browser may use to provide [IP anonymization](./anonymous-client-ip.md). Feedback on [private prefetch proxies](https://github.com/buettner/private-prefetch-proxy/issues) is welcome, but tracked separately.

## The proposal

This explainer proposes a new way for content to declare what kind of speculation the user agent may do about future user activity, especially outgoing navigation, in order to reduce user-visible latency. This speculation may have side effects, but an author's declaration that certain speculative activity is productive enables the user agent to speculate more often.

It is intended to be more general than existing resource hints for navigation, and allows the author to make even weak declarations about the likelihood that the navigation will occur. The user agent can combine this with its own heuristics to decide whether to speculate.

The rules are expressed as a JSON object included within a script tag (like [import maps][import-maps]). Currently, like import maps, we only allow inline script tags for speculation rules; future extensions may allow external ones.

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

## Future extensions

### Scores

A rule may include a _score_ between 0.0 and 1.0 (inclusive), defaulting to 0.5, which is a hint about how likely the user is to navigate to the URL. It is expected that UAs will treat this monotonically (i.e., all else equal, increasing the score associated with a rule will make the UA speculate no less than before for that URL, and decreasing the score will not make the UA speculate where it previously did not). However, the user agent may select a link with a lower author-assigned score than another if its heuristics suggest it is a better choice.

A modification of the above example, which works off of the highly-sophisticated model that people tend to click on the top-voted link more often than the later ones, would be:

```json
{"prefetch": [
  {"source": "list",
   "urls": ["/item?id=32480009"],
   "score": 0.8},
  {"source": "list",
   "urls": [
    "https://support.signal.org/hc/en-us/articles/4850133017242",
    "https://discord.com/blog/how-discord-supercharges-network-disks-for-extreme-low-latency",
    "https://github.com/containers/krunvm"
   ],
   "score": 0.5}
]}
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

```js
{
  "prerender": [
    {"source": "document",
     "where": {"and": [
       {"href_matches": "/*"},
       {"not": {"href_matches": "/logout"}},
       {"not": {"selector_matches": ".no-prerender"}}
     ]},
     "score": 0.1}
  ]
}
```

Note how this example uses a low `"score"` value to indicate that, although these links are _safe_ to prerender, they aren't necessarily that important or likely to be clicked on. In such a case, the browser would likely use its own heuristics, e.g. only performing the prerender on pointer-down. Additionally, the web developer might combine this with a higher-scoring rule that indicates which URLs they suspect are likely, which the browser could prerender ahead of time.

#### Alternatives

There are a number of alternatives to this that were not selected, such as:

* **Implicit `"and"` on conditions.** A straw poll suggested this wasn't obvious, and making this explicit made it easier to understand.
* **A bespoke parsed expression syntax.** This has nice ergonomic properties for complex expressions, but expressions are expected to be fairly simple in practice. If strings like selectors and URL patterns might be controlled by an attacker, this would also potentially introduce injection vulnerabilities (along the lines of XSS and SQL injection), unless an even more cumbersome syntax (along the lines of prepared statements) were used. This would also generally be more difficult to programmatically manipulate, whereas keeping this in pure JSON allows existing JSON tooling in various languages (but most notably JavaScript and web browsers) to be manipulate it.
* **Combining negation with conditions.** Given the desire to provide more general logic primitives, this would be somewhat surprising. Negation with a separate object is longer but not dramatically longer. In the case of CSS selectors, a shorter syntax for negation is already available even without support at this level (namely, the `:not(...)` pseudo-class).

### Handler URLs

Another possible future extension, which would likely need to be restricted to same-origin URLs, could allow the actual URL to be preloaded to be different from the navigation URL (but on the same origin), until the navigation actually occurs. This could allow multiple possible destinations with a common "template" (e.g., product detail pages) to preload just the template. This preloaded page could then be used regardless of which product the user selects.

```json
{"prerender": [
  {"source": "document",
   "if_href_matches": ["/details/([a-z0-9-]+)"],
   "handler": "/details/_prerender"}
]}
```

### External speculation rules

Like import maps, speculation rules are currently inline-only, with the speculation rules JSON being contained in the `<script>` element's child text content. However, [like import maps](https://github.com/WICG/import-maps/issues/235), it would be convenient for authors if we allowed `<script type="speculationrules">` to instead have an `src=""` attribute pointing to an external URL.

Some questions to answer here are the interaction with CSP, and whether a dedicated MIME type is necessary. The answers might not necessarily be the same for import maps and speculation rules, since import maps give a more direct ability to interfere with script execution.

### More speculation actions

As mentioned previously, we have currently only specified `"prefetch"` and `"prerender"` speculation actions.

Adding `"dns-prefetch"` and `"preconnect"`, to mirror [Resource Hints](https://w3c.github.io/resource-hints/), would be an obvious extension, simply giving a more-ergonomic and capable way of triggering those actions.

Another envisioned speculative action is `"prefetch_with_subresources"`, which prefetches a document and then uses the HTML preload scanner to find other subresources that are worth preloading. Chromium currently does something similar (known as "[NoState Prefetch](https://developer.chrome.com/blog/nostate-prefetch/)") for `<link rel="prerender">`. But, we're not yet sure this feature is pulling its weight, in between the lightweight prefetch and the fully-instant prerender features, so it's not yet clear whether this will be worth integrating.

## Proposed processing model

Conceptually, the user agent may from time to time execute a task to consider speculation. (In practice, it will likely do this only in response to some sort of DOM mutation or other event that indicates the applicable rules have changed, and may limit its attention to the affected parts of the document.) Changes to the DOM that are undone within a task cannot therefore be observed by this algorithm.

To consider speculation is to look at the computed ruleset for the document (merging, if there are multiple), gather a list of candidate URLs, combine the author-declared likelihood with its own heuristics (which may include device or network characteristics, page structure, the viewport, the location of the cursor, past activity on the page, etc.), and thus select a subset of the allowed actions to execute speculatively.

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

As mentioned in [the Goals section](#goals), `<link>` also doesn't lend itself to reducing duplication with anchors alread in the document, requiring the author to either statically insert the full set of links into the document resource (and since they appear in the `<head>`, this implies buffering) or dynamically synchronize the links in the page with `<link>` references in the head, potentially updating them as script mutates the document.

With [document rules](#document-rules), we can do much better.

### Alternatives to `"target_hint"`

One alternative to the explicit [`"target_hint"`](#window-name-targeting-hints) field is for implementations such as Chromium, which need to know the target window before prerendering, to use heuristics to try to figure out the target window. For example, given a prerender rule targeting a given URL, they could scan for links to that URL in the current DOM, and use that link's `target=""` to guess at the target window.

This has a few disadvantages:

- It doesn't work for certain navigations:
  - Those triggered via JavaScript, e.g. `<button onclick="window.open(url)">`.
  - Those triggered via links that are not yet in the DOM at the time the prerendering occurs, e.g. those due to clicking inside a pop-up which is inserted dynamically.
- It is slightly more costly for performance, requiring a scan of the entire DOM whenever speculation rules are updated.

We worry that such a technique might encourage developers to insert hidden fake links into the DOM to trigger the heuristic.

[import-maps]: https://github.com/WICG/import-maps
[resource-hints]: https://github.com/w3c/resource-hints
[selector-match]: https://drafts.csswg.org/selectors-4/#match-a-selector-against-an-element
[selectors]: https://drafts.csswg.org/selectors/
[urlpattern]: https://github.com/WICG/urlpattern
[webdriver]: https://github.com/w3c/webdriver
