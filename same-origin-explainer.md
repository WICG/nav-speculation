# Same-origin prerendering explainer

## Introduction

This explainer covers the specific case of same-origin prerendering triggered by the [speculation rules API](triggers.md). For a comprehensive explainer of general prerendering, see [Prerendering, revamped](README.md).

This feature enables authors to provide a hint to the browser to prerender a URL, so the end-user can experience a near-instantaneous page load if that URL is visited.

## Goals

* Provide users with near-instantaneous page loads when there is a likely next URL to be visited.
* Prevent the prerendering page from disrupting the user's experience. For example, it should not be able to play audio, change UI elements, etc.

## How it works

A prerendered page is created when the browser acts on a hint to prerender a URL. A browsing context is created in the background, and navigates to the URL in that context. This is called the ***initial prerender navigation***.

A subsequent navigation in the main browsing context to that URL ***activates*** the prerendered page. Activation presents the prerendered page in the main browsing context like a normal page.

Sometimes a prerendered page is not activated and instead is discarded. This can happen for several reasons, such as the URL is not navigated to next, user-agent imposed restrictions, or the prerendered page attempted an operation that could not be handled gracefully during prerendering.

## Trigger

The [speculation rules API](triggers.md) can be used to trigger a prerender.

Example:
```html
<script type="speculationrules">
{
  "prerender": [
    {"source": "list", "urls": ["https://a.test/foo"]}
  ]
}
</script>
```

This hints to prerender `https://a.test/foo`.

As earlier mentioned, this feature is currently restricted to same-origin URLs. See [Prerendering, revamped](README.md) for considerations on how to later support cross-origin prerendering in a privacy-preserving way.

## `document.prerendering`

A document can tell it is being prerendered with `document.prerendering`. Upon activation, a `prerenderingchange` event is dispatched on the document.

Example:
```javascript
console.log(document.prerendering);  // true

document.addEventListener('prerenderingchange', (event) => {
  console.log(document.prerendering);  // false
});
```

## Storage and cookies

The prerendered page has the same access to storage and cookies as a normal page. In particular, the prerendered request includes cookies and the Set-Cookie response header modifies cookies. Storage APIs such as Indexed DB and LocalStorage also function in a prerendered page.

### Session Storage

Session storage is a special case. Session storage is intended to be restricted to a tab, but allowing a prerendering page to access its tab's session storage may cause breakage for sites that expect only one page capable of accessing the tab's session storage at a time. Therefore a prerendered page starts out with a clone of the tab's session storage state when it is created. Upon activation, the prerendered page's clone is discarded, and again the tab's main storage state is used instead. Pages that use session storage can use the `prerenderingchange` event to detect when this swapping of state occurs.

See [this discussion](https://github.com/whatwg/storage/issues/119) for more rationale about this design.

## Restricted APIs

Some restrictions apply to prerendered pages, to prevent intrusive behaviors such as popping up windows, playing audio, etc.

Many APIs are simply deferred in a prerendered page, that is, the processing does not occur until activation. If the API is promise-based, the promise is not resolved until activation. Some examples of these APIs include Geolocation, Web Serial, Notifications, Web MIDI, and Idle Detection.

It is worth noting that APIs gated on user interaction, system focus, or visibilty are implicitly restricted in a prerendered page, since prerendered pages never have those properties. This includes `window.open()`, `element.requestFullscreen()`, and more.

See the [Preventing intrusive behaviors](https://jeremyroman.github.io/alternate-loading-modes/#intrusive-behaviors) section of the specification for a list of restrictions, while this is still a work-in-progress.

The user agent may also discard a prerendered page at any time, and some implementations may do this when they do not yet support deferring or handling an API in a graceful manner. For example, Chromium's implementation discards prerendered pages that use plugins.

## Resource requests

Generally, prerendered pages can load resources like a normal page. As mentioned earlier, cookies are included on these requests as usual.

However, cross-origin iframes delay loading until after activation. This is partially to avoid breakage caused by loading a cross-origin site that is unaware of prerendering.

### Timing APIs

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

## Considered alternatives

### Prefetching

Chromium previously supported prerendering, but replaced it with [NoState Prefetch](https://developers.google.com/web/updates/2018/07/nostate-prefetch). No State Prefetch prefetches a page and scans its markup for resources that are also fetched.

The primary advantage of prerendering over prefetching is that users perceive near-instantaneous page loads with prerendering, since a page that already exists in the background is just swapped into view.

The primary disadvantage is that feature is much more complex for browser implementors, and some pages may need to adjust to detect prerendering by using the `document.prerendering` API if needed.

### `<link rel=prerender>`

An existing API `<link rel=prerender>` is specified today but it is not widely supported. While Chromium is listed as supporting this API, it performs a NoState Prefetch rather than a prerender.

It is possible that later the `<link rel=prerender>` API can be syntactic sugar for this feature.

## References & acknowledgements

TBD
