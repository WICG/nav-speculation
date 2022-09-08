# Same-site prerendering

[Read the spec](https://wicg.github.io/nav-speculation/prerendering.html)

Prerendering allows user-agents to preemptively load content into an invisible separate tab, allowing a near-instantaneous loading experience when the user navigates to that content, by displaying that tab instead of reloading the content.

Prerendering can potentially be triggered by another referrer document, or by the [user agent](https://wicg.github.io/nav-speculation/prerendering.html#start-user-agent-initiated-prerendering), for example from browser UI such as the URL bar.

Our current specification, and the Chromium implementation, only allow same-site referrer documents. Allowing cross-site referrer documents requires additional security and privacy considerations, which we have many ideas for but have not yet proven out. As such, this explainer is scoped to same-site-document- and user-agent-initiated prerendering, often abbreviated to "same-site prerendering".

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [How it works](#how-it-works)
- [Examples](#examples)
  - [User-agent initiated prerendering](#user-agent-initiated-prerendering)
  - [Page-initiated prerendering](#page-initiated-prerendering)
- [Opting out](#opting-out)
- [Restrictions](#restrictions)
  - [No cross-site navigations](#no-cross-site-navigations)
  - [Cross-origin same-site navigations require opt-in](#cross-origin-same-site-navigations-require-opt-in)
  - [Restrictions on the basis of being hidden](#restrictions-on-the-basis-of-being-hidden)
  - [Restrictions on loaded content](#restrictions-on-loaded-content)
  - [Purpose-specific APIs](#purpose-specific-apis)
  - [Workers](#workers)
- [Storage and cookies](#storage-and-cookies)
  - [`sessionStorage`](#sessionstorage)
- [Prerendering state API](#prerendering-state-api)
- [Timing](#timing)
- [Page lifecycle and freezing](#page-lifecycle-and-freezing)
- [Session history](#session-history)
- [Rendering-related behavior](#rendering-related-behavior)
- [CSP integration](#csp-integration)
- [More details on cross-origin same-site](#more-details-on-cross-origin-same-site)
- [Considered alternatives](#considered-alternatives)
  - [Main-document prefetching](#main-document-prefetching)
  - [Prefetching with subresources](#prefetching-with-subresources)
  - [Integration with `<link rel=prerender>`](#integration-with-link-relprerender)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## How it works

Prerendering is implemented by loading content into a [prerendering browsing context](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context), which is a new type of [top-level browsing context](https://html.spec.whatwg.org/multipage/browsers.html#top-level-browsing-context). A prerendering browsing context can be thought of as a tab that is not yet shown to the user, and which the user has not yet affirmatively indicated an intention to visit. As such, it has additional restrictions placed on it to prevent user-visible disruptions and avoid the prerendered page from performing any tasks which only a user-visible page should be allowed to do.

Prerendering browsing contexts can be [activated](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context-activate), which causes them to transition to being full top-level browsing contexts (i.e. tabs). From a user experience perspective, activation acts like an instantaneous navigation, since unlike normal navigation it does not require a network round-trip, creation of a `Document`, or running initialization JavaScript provided by the web developer. The majority of that has already been done in the prerendering browsing context. The majority but not always all of it — the site might delay some of its initialization until activation, or some of the initialization might not have finished, especially if the browser deprioritizes unactivated browsing contexts.

Activation of a prerendering browsing context is done by the user agent, when it notices a navigation that could use the prerendered contents.

Documents rendered within a prerendering browsing context have the ability to react to activation, which they can use to upgrade themselves once free of the restrictions. For example, they could start using permission-requiring APIs, or choose to load some of the resources only after the context has been activated.

_Note: a browsing context is the right primitive here, as opposed to a `Window` or `Document`, as we need these restrictions to apply even across navigations. For example, if you prerender `https://a.example/` which contains `<meta http-equiv="refresh" content="0; URL=https://a.example/home">` then we need to continue applying these restrictions while loading the `/home` page._

## Examples

### User-agent initiated prerendering

Consider that the user types the url `b.exa` in the address bar, and the user-agent decides that they're very likely to browse to `https://b.example`.

The browser creates a prerendering browsing context, which it navigates to `https://b.example/`. This navigation takes place with a [`Sec-Purpose` header](https://wicg.github.io/nav-speculation/prefetch.html#sec-purpose-header), which gives `https://b.example/` a chance to [opt-out](#opting-out) from being prerendered.

Within this prerendering browsing context, assuming the prerender request succeeded, loading of `https://b.example/` proceeds mostly as normal. This includes any expensive in-document JavaScript necessary to initialize the content found there. It could even include server- or client-side redirects to other pages from the same origin.

However, if `https://b.example/` requests notification permissions on first load, such a permission prompt will only be shown when the user navigates to `https://b.example` and the tab is displayed. Similarly, if `https://b.example/` performs an `alert()` call, the call will instantly return, without the user seeing anything.

Now, the user finishes typing `b.example` and pressed the Return key. At this point the user agent notices that it has a prerendering browsing context originally created for `https://b.example/`, so it activates it and upgrades the invisible tab into a full-blown, displayed tab. Since `https://b.example/` was already loaded in the prerendering browsing context, this navigation occurs seamlessly and instantly, providing a great user experience.

Upon activation, `https://b.example/` gets notified via [the API](#prerendering-state-api). At this point, it now has access to many of the previously restricted APIs, so it can upgrade itself.

```js
Notification.requestPermission().then(() => {
  // continue based on information received after activation
});
```

This completes the journey to a fully-rendered view of `https://b.example/`, in a user-visible top-level browsing context.

### Page-initiated prerendering

The [speculation rules API](./triggers.md) can be used to trigger a prerender to any same-site page. For example:

```html
<script type="speculationrules">
{
  "prerender": [
    {"source": "list", "urls": ["https://a.test/foo"]}
  ]
}
</script>

<a href="https://a.test/foo">Click me!</a>
```

The `<script type="speculationrules">` block here hints to prerender `https://a.test/foo`. As in the previous section, such prerendering includes sending the `Sec-Purpose` header. If the prerendered URL is cross-site, then prerendering will fail. If it is same-site but cross-origin, then the destination needs the opt-in [`Supports-Loading-Mode: credentialed-prerender` header](./opt-in.md#cross-origin-same-site-prerendering). See [below](#more-details-on-cross-origin-same-site) for more details on the same-site cross-origin case.

Note that the user agent remains in control of exactly when this prerendering is done; it could do it immediately upon script insertion, or it could do it in idle time, or it could do it as the user starts clicking on the link, or it could do it never. But if it does prerender that URL, then any navigation there will activate the prerendering browsing context, with the resulting desired instant navigation.

## Opting out

When a document is fetched for the purpose of prerendering, the user-agent sends an additional header: `Sec-Purpose: prefetch; prerender`. See [the spec](https://wicg.github.io/nav-speculation/prefetch.html#sec-purpose-header) for more details.

The server may decide at this point to cancel the prerendering, which would cause a full load of the document once the user performs an actual navigation to the URL, by responsing with an HTTP error or without a response body, [as described here](https://wicg.github.io/nav-speculation/prerendering.html#no-bad-navs).

Developers might decide to implement such a response, for example, in order to reduce server load in cases where there are too many unfulfilled prerenders, or if prerendering may cause the page to reach some error condition.

The recommended response codes for opting out of prerendering are [204 No Content](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/204), implying that the server has acknowledged that prerendering was requested but no document is served, or [503 Service Unavailable](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503), implying that prerendering is not an available service. However, any other 4xx/5xx response code would have the same effect.

## Restrictions

For an API-by-API analysis of the restrictions in prerendering browsing contexts, see [this section of the spec](https://wicg.github.io/nav-speculation/prerendering.html#intrusive-behaviors). The following section outlines the reasoning behind the proposed restrictions.

### No cross-site navigations

If the prerendering browsing context navigates to a different site, then it will be immediately discarded before a request to that other site is sent. As such, it will no longer be used for any future activation.

This includes both cases where the initial request redirects to a different site through the `Location` header, or cases where the navigation occurs after the initial document is loaded, via mechanisms like the `location.href` setter or the `<meta http-equiv="refresh">` element.

### Cross-origin same-site navigations require opt-in

If the prerendering browsing context navigates to a different origin that is still same-site, then (unlike the cross-site case) the request will be made. However, the response will immediately be checked for the `Supports-Loading-Mode: credentialed-prerender` header; if it is not present, then the response will be discarded and the prerender will fail.

Again, this includes both cases where the initial request redirects to a different origin through the `Location` header, or cases where the navigation occurs after the initial document is loaded, via mechanisms like the `location.href` setter or the `<meta http-equiv="refresh">` element.

For more analysis on cross-origin same-site prerendering, see [our dedicated section below](#more-details-on-cross-origin-same-site).

### Restrictions on the basis of being hidden

While prerendered, pages are additionally restricted in various ways due to the fact that the user has not yet expressed any intent to interact.

- Some APIs with a clear async boundary will have their work delayed until activation. Thus, their corresponding promises would simply remain pending, or their associated events would not fire. This includes features that are controlled by the [Permissions API](https://w3c.github.io/permissions/) ([list](https://w3c.github.io/permissions/#permission-registry)), some features that are controlled by [Permissions Policy](https://w3c.github.io/webappsec-permissions-policy/), pointer lock, and orientation lock (the latter two of which are controlled by `<iframe sandbox="">`).

- Any feature which requires [user activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation) will not be available, since user activation is not possible in prerendering browsing contexts. This includes APIs like `PresentationRequest` and `PaymentRequest`, as well as the `beforeunload` prompt and `window.open()`.

- The gamepad API will return "no gamepads" pre-activation, and fire `gamepadconnected` as part of activation (after which it will return the usual set of gamepads).

- Autoplaying content will fetch the content that is about to be autoplayed, but the playing will start in practice only when the document is activated.

- Downloads will be delayed until after activation.

- `window.alert()` and `window.print()` will silently do nothing pre-activation.

- `window.confirm()` and `window.prompt()` will silently return their default values (`false` and `null`) pre-activation.

Note that, because implementations are allowed to discard a prerendering browsing context at any time, some implementations might choose to discard in reaction to some of these APIs being called, instead of delaying. This is expected to change over time: it can be easier to start by implementing discarding, but eventual put in extra engineering work to move to a delay model. The specification includes the delay model in all cases where it makes sense, to allow such future movement.

### Restrictions on loaded content

To simplify implementation, specification, and the web-developer facing consequences, prerendering browsing contexts cannot host non-HTTP(S) top-level `Document`s. In particular, they cannot host:

- `javascript:` URLs
- `data:` URLs
- `blob:` URLs
- `about:` URLs, including `about:blank` and `about:srcdoc`

In some cases, supporting these would create a novel situation for a top-level browsing context: for example, right now, a top-level browsing context cannot navigate to a `data:` or `blob:` URL, so allowing those to be prerendered and then activated (which is equivalent to a navigation) would require new implementation and specification infrastructure.

In other cases, like `javascript:` URLs or `about:blank`, the problem is that those URLs generally inherit properties from their creator, and we don't want to allow this cross-`Document` influence for prerendered content. Overall, restricting to HTTP(S) URLs ensures that prerendered content always has a well-defined origin, that is not contingent on the referring page.

The removal of the script-visible `about:blank` in prerendering browsing contexts also greatly simplifies them; its existence in other browsing contexts causes `Window`s and `Document`s to lose their normally one-to-one relationship.

If a prerendering browsing context navigates itself to a non-HTTP(S) URL, e.g. via `window.location = "data:text/plain,foo"`, then the prerendering browsing context will be immediately discarded, and no longer be used by the user agent for anything.

Iframes inside of a prerendering browsing context are restricted in a slightly different way: we delay loading the contents of any cross-origin iframe while prerendering, until activation occurs. This is done to avoid breakage caused by loading a cross-origin page that is unaware of prerendering, and to avoid the complexities around what credentials and storage to expose to these frames.

### Purpose-specific APIs

To react to changes in prerendering state, script can use APIs particular to the behavior they are interested in. For example, the [Notification API](https://notifications.spec.whatwg.org/)  can be used in supporting browsers to request permission to show a notification. Since permission-granting is automatically delayed until activation, the normal permission-requesting code could be used. For example, to prompt for notifications, you'd just write:

```js
Notification.requestPermission().then(state => {
  // This will be called only after the user grants or denies the permission.
  // - If the page is rendered normally, that will probably be soon.
  // - If the page is rendered in a prerendering browsing context, then the prompt will be delayed until activation.
});
```

Similar restrictions apply to the [Geolocation API](https://w3c.github.io/geolocation-api),the [Idle Detection API](https://wicg.github.io/idle-detection/), the [Generic Sensor API](https://w3c.github.io/sensors/), and many other APIs as described in detail [in this section](https://wicg.github.io/nav-speculation/prerendering.html#delay-async-apis).

### Workers

To prevent overuse of resources by prerendered pages, worker execution is delayed until activation. This includes dedicated workers, shared workers and service workers.

Note that service workers that are already registered would handle fetches from prerendered page and those pages would be visible to them as [Clients](https://w3c.github.io/ServiceWorker/#client-interface).

## Storage and cookies

For same-site prerendering, the prerendered page has the same access to storage and cookies as a normal page. In particular, the prerendered request includes cookies, and the `Set-Cookie` response header modifies cookies. Storage APIs such as Indexed DB and `localStorage` also function in a prerendered page.

### `sessionStorage`

`sessionStorage` is a special case. Session storage is intended to be restricted to a tab, but allowing a prerendering page to access its tab's session storage may cause breakage for sites that expect only one page capable of accessing the tab's session storage at a time. Therefore a prerendered page starts out with a clone of the tab's session storage state when it is created. Upon activation, the prerendered page's clone is discarded, and again the tab's main storage state is used instead. Pages that use session storage can use the `prerenderingchange` event to detect when this swapping of state occurs.

See [this discussion](https://github.com/whatwg/storage/issues/119) for more rationale about this design.

## Prerendering state API

For cases related to rendering and visibility, the document is extended to include a [dedicated prerendering state API](./prerendering-state.md):

```js
function afterPrerendering() {
  // start a video/animation
  // fetch large resources
  // connect to a chat server
  // etc.
}

if (document.prerendering) {
  document.addEventListener('prerenderingchange', () => {
    afterPrerendering();
  }, { once: true });
} else {
  afterPrerendering();
}
```

Please read that sibling [explainer](./prerendering-state.md) for more details on the design choices and motivations there.

## Timing

Resource Timing and Navigation Timing use the _initial prerender navigation_ as the time origin for milestones. This can be misleading because a prerendered page may have been created long before it was actually navigated to. Therefore, a new milestone for the start time of activation is added. Pages can use this milestone to measure user-perceived times.

Example:

```js
// When the activation navigation started.
let activationStart = performance.getEntriesByType('navigation')[0].activationStart;

// When First Paint occurred:
let firstPaint = performance.getEntriesByName('first-paint')[0].startTime;

// When First Contentful Paint occurred:
let firstContentfulPaint = performance.getEntriesByName('first-contentful-paint')[0].startTime;

console.log('time to first paint: ' + (firstPaint - activationStart));
console.log('time to first-contentful-paint: ' + (firstContentfulPaint - activationStart));
```

## Page lifecycle and freezing

User agents need to strike a delicate balance with prerendered content. Such content needs enough resources to do its initial setup work, so that loading it is as instant as possible. But it shouldn't consume resources in a way that would detract from a user's experience on the content they're actively viewing on the referring site.

One mechanism user agents will probably use for this is to freeze prerendered pages, in the sense defined by the [Page Lifecycle](https://wicg.github.io/page-lifecycle/) specification. The most important impact of freezing, for our purposes, is that tasks queued by the page will not be run by the event loop. In particular, we envision user agents freezing prerendered pages after some initial setup time, to avoid recurring timers or data transfers.

Using the freezing mechanism is a natural fit for prerendered content, since freezing is already performed by user agents for backgrounded content. In particular, content which uses the page lifecycle API (such as the `freeze` and `resume` events) will likely react correctly if it becomes frozen in a prerendering browsing context, just like if it were frozen in any other browsing context.

## Session history

From the user's perspective, activating a prerendering browsing context behaves like a conventional navigation. The current `Document` displayed in the prerendering browsing context is appended to session history, with any existing forward history entries pruned. Any navigations which took place within the prerendering browsing context, before activation, do not affect session history.

From the developer's perspective, a prerendering browsing context can be thought of as having a trivial [session history](https://html.spec.whatwg.org/multipage/history.html#the-session-history-of-browsing-contexts) where only one entry, the current entry, exists. All navigations within the prerendering browsing context are effectively done with replacement. While APIs that operate on session history, such as [window.history](https://html.spec.whatwg.org/multipage/history.html#the-history-interface), can be called within prerendering browsing contexts, they only operate on the context's trivial session history. Consequently, prerendering browsing contexts do not take part in their referring page's joint session history; that is, they cannot navigate their referrer by calling `history.back()` enough times, like iframes can navigate their embedders.

This model ensures that users get the expected experience when using the back button, i.e., that they are taken back to the last thing they saw. Once a prerendering browsing context is activated, only a single session history entry gets appended to the joint session history, ignoring any previous navigations that happened within the prerendering browsing context. Then, stepping back one step in the joint session history, e.g. by pressing the back button, takes the user back to the referrer page.

## Rendering-related behavior

Prerendered content needs to strike a delicate balance, of doing enough rendering to be useful, but not actually displaying any pixels on the user's screen. As such, we want developers to avoid performing expensive work which is not beneficial while being prerendered. And ideally, doing this should require minimal additional coding by the developer of the page being prerendered.

Generally speaking, our plan is to treat content as if it were in a "background tab": it will still perform layout, using (for [privacy and simplicity reasons](#communications-channels-that-are-blocked)) the creation-time size of the referring page as the viewport. Rendering APIs which communicate visibility information, such as [Intersection Observer](https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API) or the [`loading` attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-loading), will indicate visibility based on the creation-time viewport.

## CSP integration

A prerendered `Document` can apply CSP to itself as normal. Being in a prerendering browsing context vs. a normal top-level browsing context does not change any of the impacts of CSP. Note that since prerendered documents are [always loaded from HTTP(S) URLs](#restrictions-on-loaded-content), there is no need to worry about complex CSP inheritance semantics.

Prerendered content will be affected by [`prefetch-src`](https://w3c.github.io/webappsec-csp/#directive-prefetch-src) on the referring page, which provides a way of preventing prefetching in addition to the [triggers](./triggers.md).

## More details on cross-origin same-site

Recall that the web's privacy boundary is the site, whereas its security boundary is an origin. So although it's obviously safe to allow same-origin prerendering, cross-origin same-site prerendering requires some additional analysis, to ensure that we are not introducing any security issues.

Here is what we've found after doing such analysis:

- Side effects from prerendering are the biggest potential attack.
  - Side effects from simply issuing credentialed requests to the target URL, e.g. triggering non-idempotent GETs, are not a concern. These are already possible today via `<iframe>`s, `<img>`s, etc.
  - Thus, the main worry is side effects from actually prerendering the page, e.g. running its JavaScript. To prevent these, we require the [`Supports-Loading-Mode: credentialed-prerender`](./opt-in.md#cross-origin-same-site-prerendering) header.

- Preventing side channel attacks such as [Spectre](https://en.wikipedia.org/wiki/Spectre_(security_vulnerability)) requires respecting the [cross-origin isolation](https://web.dev/coop-coep/) settings of both the referrer and destination. In particular, we must treat prerendered pages like we treat popups, such that they go into agent clusters segregated by cross-origin isolation status, and thus in implementations they go into different processes when appropriate. Thankfully, this is fairly automatic in the relevant spec infrastructure.

- One might be concerned about cross-origin information leakage via [`activationStart`](#timing), since normally timing APIs are carefully guarded to make sure they don't leak information across origins. However, this particular piece of timing information is not an issue: it is just the time that the prerender was activated, and represents something about the prerendered page, not information about the referrer page.

- The default referrer policy on the web is `"strict-origin-when-cross-origin"`. This means that if `https://a.example.com/1.html` prerenders `https://a.example.com/2.html`, the full referrer will be sent. But if the same referrer document prerenders `https://b.example.com/2.html`, only the origin (`https://a.example.com/`) will be sent, losing the `1.html` path. This is fine and working as expected; it's just something for developers to be aware of.

## Considered alternatives

### Main-document prefetching

Prefetching the main response for an upcoming navigation, without prefetching any subresources or actually creating the document and running any of its JavaScript, is a technique we also believe is important. It has its [own specification](https://wicg.github.io/nav-speculation/prefetch.html) in this repository.

Main-document prefetching has an advantage over prerendering in its simplicity. Because no JavaScript runs, there are many fewer considerations. And because only one resource is fetched, it's possible to come up with reasonable cross-site semantics, at least in the case where the target has no existing HTTP state (credentials and cache).

However, it is not necessarily going to lead to instant navigations, like prerendering can.

### Prefetching with subresources

Chromium previously supported prerendering, but replaced it with "[NoState Prefetch](https://developers.google.com/web/updates/2018/07/nostate-prefetch)". No State Prefetch prefetches a page and scans its markup for resources that are also fetched. A less Chromium-specific name for this technology would then be "prefetching with subresources".

This is another point on the spectrum between main-document prefetching, and prerendering. It avoids the complexities of running JavaScript, so it is simpler than prerendering; but it does fetch more than one resource, so it is not as straightforward what to do in the cross-site case compared to main-document prefetching.

Based on some initial performance testing, Chromium found that prefetching with subresources was a bad middle ground for our users: it would result in significantly more resource consumption, but only slightly faster loads, compared to main-document prefetching. As such, we're currently investing in main-document prefetching and in prerendering instead. We may revisit prefetching with subresources at some point in the future.

### Integration with `<link rel=prerender>`

An existing API `<link rel=prerender>` is specified today but it is not widely supported. While Chromium is listed as supporting this API, it performs a NoState Prefetch (prefetch with subresources) rather than a prerender.

It is possible that later the `<link rel=prerender>` API can be used as a simpler version of the [speculation rules API](./triggers.md). However, that might have compatibility concerns, so perhaps it's best to leave this link relationship behind.
