# Prerendering

## The Feature

Prerendering allows user-agents to preemprively load content into an invisible separate tab, allowing a near-instantaneous loading experience when the user navigates to that content, by displaying that tab instead of reloading the content.

## Triggering
Prerendering can potentially be [triggered]('./triggers.md') by another document (an "initiator") or by the [user agent](https://wicg.github.io/nav-speculation/prerendering.html#start-user-agent-initiated-prerendering), for example from browser UI such as the URL bar ("omnibox"). The purpose of this explainer is to focus solely on user-agent triggering.

## How It Works

Prerendering is implemented by loading content into a [prerendering browsing context](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context), which is a new type of [top-level browsing context](https://html.spec.whatwg.org/multipage/browsers.html#top-level-browsing-context). A prerendering browsing context can be thought of as a tab that is not yet shown to the user, and which the user has not yet affirmatively indicated an intention to visit. As such, it has additional restrictions placed on it to protect the user's privacy and prevent disruptions.

Prerendering browsing contexts can be [activated](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context-activate), which causes them to transition to being full top-level browsing contexts (i.e. tabs). From a user experience perspective, activation acts like an instantaneous navigation, since unlike normal navigation it does not require a network round-trip, creation of a `Document`, or running initialization JavaScript provided by the web developer. The majority of that has already been done in the prerendering browsing context. The majority but not always all of it - the site might delay some of its initialization until activation, or some of the initialization might not have finished, especially if the browser deprioritizes unactivated browsing contexts.

Activation of a prerendering browsing context is done by the user agent, when it notices a navigation that could use the prerendered contents.

Documents rendered within a prerendering browsing context have the ability to react to activation, which they can use to upgrade themselves once free of the restrictions. For example, they could start using permission-requiring APIs, or get access to unpartitioned storage, or choose to load some of the resources only after the context has been activated.

_Note: a browsing context is the right primitive here, as opposed to a `Window` or `Document`, as we need these restrictions to apply even across navigations. For example, if you prerender `https://a.example/` which contains `<meta http-equiv="refresh" content="0; URL=https://a.example/home">` then we need to continue applying these restrictions while loading the `/home` page._

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [Prerendering](#prerendering)
  - [The Feature](#the-feature)
  - [Triggering](#triggering)
  - [How It Works](#how-it-works)
  - [Table of contents](#table-of-contents)
  - [Example](#example)
  - [Opting Out](#opting-out)
  - [Restrictions](#restrictions)
    - [Privacy-based restrictions](#privacy-based-restrictions)
    - [Restrictions on the basis of being hidden](#restrictions-on-the-basis-of-being-hidden)
    - [Restrictions on loaded content](#restrictions-on-loaded-content)
    - [Purpose-specific APIs](#purpose-specific-apis)
    - [Workers](#workers)
  - [Prerendering State API](#prerendering-state-api)
  - [Timing](#timing)
  - [Page lifecycle and freezing](#page-lifecycle-and-freezing)
  - [Session history](#session-history)
  - [Rendering-related behavior](#rendering-related-behavior)
  - [CSP integration](#csp-integration)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Example

Consider that the user types the url `b.exa` in the address bar, and the user-agent decides that
they're very likely to browse to `https://b.example`.

The browser creates a prerendering browsing context, which it navigates to `https://b.example/`. This navigation takes place with a [`Sec-Purpose` header](https://wicg.github.io/nav-speculation/prefetch.html#sec-purpose-header), which gives `https://b.example/` a chance to [opt-out](#opting-out) from being prerendered.

Within this prerendering browsing context, assuming the prerender request succeeded, loading of `https://b.example/` proceeds mostly as normal. This includes any expensive in-document JavaScript necessary to initialize the content found there. It could even include server- or client-side redirects to other pages from the same origin.

However, if `https://b.example/` requests notification permissions on first load, such a permission prompt will only be shown when the user navigates to `https://b.example` and the tab is displayed. Similarly, if `https://b.example/` performs an `alert()` call, the call will instantly return, without the user seeing anything.

Now, the user finishes typing `b.example` and pressed the Return key. At this point the user agent notices that it has a prerendering browsing context originally created for `https://b.example/`, so it activates it and upgrades the invisible tab into a full-blown, displayed tab. Since `https://b.example/` was already loaded in the prerendering browsing context, this navigation occurs seamlessly and instantly, providing a great user experience.

Upon activation, `https://b.example/` gets notified via [the API](#prerendering-state-api). At this point, it now has access many of the previously restricted APIs, so it can upgrade itself.

```js
Notification.requestPermission().then(() => {
  // continue based on information received after activation
});
```

This completes the journey to a fully-rendered view of `https://b.example/`, in a user-visible top-level browsing context.

## Opting Out

When a document is fetched for the purpose of prerendering, the user-agent sends an additional header: `Sec-Purpose: prefetch; prerender`. See [the spec](https://wicg.github.io/nav-speculation/prefetch.html#sec-purpose-header) for more details.

The server may decide at this point to cancel the prerendering, which would cause a full load of the document once the user performs an actual navigation to the URL, by responsing with an HTTP error or without a response body, [as described here](https://wicg.github.io/nav-speculation/prerendering.html#no-bad-navs).

Developers might decide to implement such response, for example, in order to reduce server load in case where there are too many unfulfilled prerenders, or if prerendering may cause the page to reach some error condition.

The recommended response codes for opting out of prerendering are [204 No Content](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/204), implying that the server has acknowledged that prerendering was requested but no document is served, or [503 Service Unavailable](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503), implying that prerendering is not an available service. However, any other 4xx/5xx response code would have the same effect.

## Restrictions

For an API-by-API analysis of the restrictions in prerendering browsing contexts, see [this section of the spec](https://wicg.github.io/nav-speculation/prerendering.html#intrusive-behaviors). The following section outlines the reasoning behind the proposed restrictions.

### Privacy-based restrictions

Since the first version of prerendering only supports user-agent initiated prerendering, the cross-origin concerns between the prerendered page and its initiator do not applied. Once prerendering can be [triggered](./triggers.md), some of the restrictions mentioned [here]('./browsing-context.bs) will apply.

The main privacy-based restriction at this phase is that loading cross-origin iframes is deferred until activation, and top-level navigation to a different origin would cancel the prerendering.

### Restrictions on the basis of being hidden

While prerendered, pages are additionally restricted in various ways due to the fact that the user has not yet expressed any intent to interact.

- Some APIs with a clear async boundary will have their work delayed until activation. Thus, their corresponding promises would simply remain pending, or their associated events would not fire. This includes features that are controlled by the [Permissions API](https://w3c.github.io/permissions/) ([list](https://w3c.github.io/permissions/#permission-registry)), some features that are controlled by [Permissions Policy](https://w3c.github.io/webappsec-permissions-policy/), pointer lock, and orientation lock (the latter two of which are controlled by `<iframe sandbox="">`).

- Any feature which requires [user activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation) will not be available, since user activation is not possible in prerendering browsing contexts. This includes APIs like `PresentationRequest` and `PaymentRequest`, as well as the `beforeunload` prompt and `window.open()`.

- The gamepad API will return "no gamepads" pre-activation, and fire `gamepadconnected` as part of activation (after which it will return the usual set of gamepads).

- Autoplaying content will fetch the content that is about to be autoplayed, but the playing will start in practice only when the document is activated.

- Downloads will be delayed until after activation.

- `window.alert()` and `window.print()` will silently do nothing pre-activation.

- `window.confirm()` and `window.prompt()` will silently return their default values (`false` and `null`) pre-activation.


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

Note that iframes (nested browsing contexts) inside of a prerendered browsing context have no such restrictions.

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

## Prerendering State API

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
Resource Timing and Navigation Timing use the <em>initial prerender navigation</em> as the time origin for milestones. This can be misleading because a prerendered page may have been created long before it was actually navigated to. Therefore, a new milestone for the start time of activation is added. Pages can use this milestone to measure user-perceived times.

Example:
```javascript
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

