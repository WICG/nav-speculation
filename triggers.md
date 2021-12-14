# Triggers for Prefetching, Prerendering, etc.

A web-facing "trigger" is a mechanism for web content to permit prefetching or prerendering of certain URLs.

For example, a prerendering trigger conveys to the browser:
* the user is reasonably **likely to navigate** to the URL
* prefetching the URL is not believed to have undesirable **side effects**, at least under certain conditions
* the response body is expected to be **compatible** with prerendering (i.e., the browser probably won't need to abort prerendering)

The browser need not fully trust these assertions about cross-origin URLs (those relevant for security and privacy should be verified), but having them lets the browser focus on work likely to improve navigation performance.

The existence of web-facing triggers doesn't necessarily preclude the user agent from triggering prerendering at other times, such as prerendering a user's most frequently visited sites.

[Resource Hints][resource-hints] defines the current web-facing trigger, a family of relations usable in a `<link>` element or `Link` response header. A more flexible alternative is proposed below.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Goals](#goals)
- [Non-goals](#non-goals)
- [Speculation rules](#speculation-rules)
  - [Rules](#rules)
    - [List rules](#list-rules)
    - [Document rules](#document-rules)
    - [Extension: Requirements](#extension-requirements)
    - [Extension: Handler URLs](#extension-handler-urls)
  - [Proposed Processing Model](#proposed-processing-model)
  - [Developer Tooling](#developer-tooling)
  - [Feature detection](#feature-detection)
- [Alternatives considered](#alternatives-considered)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Goals

Authors must currently **duplicate** the URLs they wish to prefetch: a `<link>` in the head of the document and an `<a>` in the body, or use script to synchronize these at runtime. Ideally, authors should be able to centrally declare which links are eligible for prefetching and prerendering without needing to rewrite the logic for emitting links into their document or write script to work around the issue.

The success of libraries like [Quicklink](https://getquick.link/) demonstrates that even relatively simple heuristics can bring significant improvements to navigation preformance and engagement. The browser is well-positioned to efficiently provide these and improve them over time, but the current scheme leaves authors to **decide for themselves**, in part by not offering wildcard matching and similar tools to identify the links which can safely be fetched.

More sophisticated authors often have aggregate **analytics**, user history on their origin, search ranking signal, or other data which provides a useful signal *in combination with* heuristics that apply in general, like the viewport-based heuristic. For best results, the browser needs a way to accept this information to make the best prediction possible.

Some sites would like to prefetch outgoing links to untrusted third-party origins **without disclosing the user's client IP address**. Browsers which can achieve this, such as through the use of a virtual private network or [private prefetch proxy](https://github.com/buettner/private-prefetch-proxy) need to be told that prefetching is acceptable *only if this mechanism is employed*, and browsers that cannot achieve this (or where the user prefers not to use it) need to understand that prefetching should not occur.

Another anticipated direction of exploration is "template" or "handler" pages which can substantially prepare for a navigation to a number of **similar pages** (e.g., a blank product detail page on an e-commerce site), without knowing which product will ultimately be selected. This would allow common markup, script and other subresources to be ready.

Accordingly, we need a trigger that is flexible enough to accommodate these and other, unanticipated, future needs. It should also **fail safe**, meaning that if new complications are added in the future, it should default to *not* making requests which may not be intended, rather thaan failing open (e.g., erroneously issuing fetches due to having ignored unsupported syntax).

## Non-goals

While we intend to better specify the behavior of "prefetch", "prerender" and similar speculated actions, these specifications are largely separable from the trigger API itself. In fact, this specified behavior should be shared as much as possible between existing resource hints, those proposed in this document, and browser features for prefetching and prerendering.

This proposal doesn't aim to address concerns about any particular provider, service or software a browser may use to provide IP anonymization. Feedback on [private prefetch proxies](https://github.com/buettner/private-prefetch-proxy/issues) is welcome, but tracked separately.

## Speculation rules

This explainer proposes a new way for content to declare what kind of speculation the user agent may do about future user activity, especially outgoing navigation, in order to reduce user-visible latency. This speculation may have side effects, but an author's declaration that certain speculative activity is productive enables the user agent to speculate more often.

It is intended to be more general than existing resource hints for navigation, and allows the author to make even weak declarations about the likelihood that the navigation will occur. The user agent can combine this with its own heuristics to decide whether to speculate.

The rules are expressed as a JSON object included within a script tag (like [import maps][import-maps]), which can be expressed inline or included as an external resource.

> This is basically because only a few elements allow the HTML parser to enter RCDATA mode, and `<script>` has already been used in this way. This doesn't necessarily mean that these rules should respect the `script-src` CSP directive. If fetched, it's not obvious whether this should permit the `application/json` MIME type or should require a specialized one like `application/speculationrules+json`. See also [discussion on WICG/import-maps](https://github.com/WICG/import-maps/issues/105#issuecomment-475330548).

The following example illustrates the basic idea:

```html
<script type="speculationrules">
{
  "prerender": [
    {"source": "list",
     "urls": ["/page/2"],
     "score": 0.5},
    {"source": "document",
     "if_href_matches": ["https://*.wikipedia.org/**"],
     "if_not_selector_matches": [".restricted-section *"],
     "score": 0.1}
  ]
}
</script>
```
The rules are divided into sections by the action, such as "dns-prefetch", "preconnect", "prefetch", "prefetch\_with\_subresources" or "prerender", that they authorize. A user agent may always choose to stop early, for instance by prefetching where prerendering was permitted.

Since these are rules for optional behavior (the UA is always free not to speculate), parsing of these can be somewhat conservative. If a UA sees a rule it does not understand, that rule is discarded. Because a rule always authorizes additional speculation (but does not confine speculation allowed by other rules), discarding rules never authorizes more speculation than the author intended, only less.

The rules are divided into a number of simple pieces that build on one another, and could be shipped largely independently, due to the conservative parsing strategy.

### Rules

A rule has a _source_ which identifies the URLs to which the rule applies.

A rule may include a _score_ between 0.0 and 1.0 (inclusive), defaulting to 0.5, which is a hint about how likely the user is to navigate to the URL. It is expected that UAs will treat this monotonically (i.e., all else equal, increasing the score associated with a rule will make the UA speculate no less than before for that URL, and decreasing the score will not make the UA speculate where it previously did not). However, the user agent may select a link with a lower author-assigned score than another if its heuristics suggest it is a better choice.

#### List rules

A list rule has an express list of the _URLs_ to which the rule applies. The list can contain any URLs, even ones for which no link or other reference to the URL exists in the document. This is especially useful in cases where the expected navigation corresponds to a link that will be added dynamically, or to an anticipated script-initiated navigation.

These URLs will be parsed relative to the document base URL (if inline in a document) or relative to the external resource URL (if externally fetched).

#### Document rules

A document rule allows the user agent to find URLs for speculation from link elements in the page. It may include criteria which restrict which of these links can be used.

The URL can be compared against [URL patterns][urlpattern] (parsed relative to the same base URL as URLs in list rules).

<dl>
<dt><code>"if_href_matches": [...]</code></dt>
<dd>requires that the link URL match at least one pattern from the list</dd>
<dt><code>"if_not_href_matches": [...]</code></dt>
<dd>requires that the link URL not match any pattern from the list</dd>
</dl>

The link element itself can also be [matched][selector-match] using [CSS selectors][selectors].

<dl>
<dt><code>"if_selector_matches": [...]</code></dt>
<dd>requires that the link element match at least one selector from the list</dd>
<dt><code>"if_not_selector_matches": [...]</code></dt>
<dd>requires that the link element not match any selector from the list</dd>
</dl>

#### Extension: Requirements

This feature is designed to allow future extension, such as a notion of requirements: assertions in rules about the capabilities of the user agent while executing them. Since user agents disregard rules they do not understand, this can be safely added later on without violating the requirements listed.

For example, an "anonymous-client-ip-when-cross-origin" requirement might mean that the rule matches only if the user agent can [prevent the client IP address from being visible to the origin server](anonymous-client-ip.md) if a cross-origin request is issued.

```json
{"prerender": [
  {"source": "document",
   "if_selector_matches": [".user-generated"],
   "requires": ["anonymous-client-ip-when-cross-origin"]}
]}
```
This would be defined to discard any rules with requirements that are not recognized or are not supported in the current configuration. Due to the conservative parsing rules, any UA which did not support requirements at all would discard all rules with requirements.

#### Extension: Handler URLs

Another possible future extension, which would likely need to be restricted to same-origin URLs, could allow the actual URL to be prerendered to be different from the navigation URL (but on the same origin), until the navigation actually occurs. This could allow multiple possible destinations with a common "template" (e.g., product detail pages) to prerender just the template. This prerendered page could then be used regardless of which product the user selects.

```json
{"prerender": [
  {"source": "document",
   "if_href_matches": ["/details/([a-z0-9-]+)"],
   "handler": "/details/_prerender"}
]}
```

### Proposed Processing Model

Conceptually, the user agent may from time to time execute a task to consider speculation (in practice, it will likely do this only in response to some sort of DOM mutation or other event that indicates the applicable rules have changed, and may limit its attention to the affected parts of the document). Changes to the DOM that are undone within a task cannot therefore be observed by this algorithm.

To consider speculation is to look at the computed ruleset for the document (merging, if there are multiple) and the candidate elements for inference (`<a>` and `<area>` elements attached to the document), gather a list of candidate URLs, combine the author-declared likelihood with its own heuristics (which may include device or network characteristics, page structure, the viewport, the location of the cursor, past activity on the page, etc), and thus select a subset of the allowed actions to execute speculatively.

At any time the user agent may decide to abort any speculation it has started, but it is never required to do so. However, if at the time of considering speculation a speculation would no longer be permitted (e.g., because the rules changed, the initiating element was modified, the document base URL changed, or another part of the document changed such that selectors no longer match), the user agent should abort the speculation if possible.

In the case where the URL is cross-origin, actions will be assumed to be versions of those actions that do not reveal user identity (preconnect with a separate socket pool, uncredentialed prefetch, uncredentialed prerender). The exact semantics of those are to be defined elsewhere.

### Developer Tooling

It will likely be useful to surface in developer tools what rules and URLs have been found, and what the heuristic probability used for each was. Developer tools should also provide an option to force the user agent to execute a speculation that it may have deemed low probability, so that the developer can reproducibly observe behavior in this case.

This information and control is important because otherwise it may be difficult to validate correct behavior as it would otherwise depend on heuristics unknown to the author. Similarly testing tools such as [WebDriver][webdriver] should likely permit overriding the user agent's selection of which valid speculations to execute.

### Feature detection

If the browser supports [HTMLScriptElement](https://html.spec.whatwg.org/multipage/scripting.html#htmlscriptelement)'s
[supports(type)](https://html.spec.whatwg.org/multipage/scripting.html#dom-script-supports) method,
`HTMLScriptElement.supports('speculationrules')` must return true.

```js
if (HTMLScriptElement.supports && HTMLScriptElement.supports('speculationrules')) {
  console.log('Your browser supports speculationrules.');
}
```

## Alternatives considered

The obvious alternative is to extend the `<link>` element.

Extending `<link>` to meet all of these needs is awkward, and somewhat inconsistent with other uses of `<link>` (which is designed to be a single non-rendered hypertext reference). In particular, adding support for requiring an anonymous client IP in a way that didn't cause existing browsers to prefetch it without such anonymization (the behavior for an unrecognized attribute is to ignore it) would take particular care.

```html
<!-- existing browsers would prefetch this directly -->
<link rel="prefetch" href="//example.org/" mustanonymize>
```

`<link>` also doesn't lend itself to reducing duplication with anchors alread in the document, requiring the author to either statically insert the full set of links into the document resource (and since they appear in the `<head>`, this implies buffering) or dynamically synchronize the links in the page with `<link>` references in the head, potentially updating them as script mutates the document.

[import-maps]: https://github.com/WICG/import-maps
[resource-hints]: https://github.com/w3c/resource-hints
[selector-match]: https://drafts.csswg.org/selectors-4/#match-a-selector-against-an-element
[selectors]: https://drafts.csswg.org/selectors/
[urlpattern]: https://github.com/WICG/urlpattern
[webdriver]: https://github.com/w3c/webdriver
