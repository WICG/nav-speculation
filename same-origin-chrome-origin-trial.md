# Chrome Origin Trial for same-origin prerendering

## Introduction

Google Chrome will offer an [origin trial](https://github.com/GoogleChrome/OriginTrials/blob/gh-pages/developer-guide.md) of [same-origin prerendering](same-origin-explainer.md) triggered by the [Speculation Rules API](triggers.md).

It is recommended to first read the feature's [explainer](same-origin-explainer.md). This document complements the explainer with information specific to the origin trial, such as quirks and limitations of Chrome's implementation today.

The origin trial is scheduled to be available in Chrome 94 through Chrome 98, approximately September 2021 to Februrary 2022.

## Local development

You can enable the feature for local development by enabling "Prerender2" in [chrome://flags](chrome://flags).

## Origin trial registration

Developers can sign up for the origin trial at (TBD link) to receive an [origin trial token](https://github.com/GoogleChrome/OriginTrials/blob/gh-pages/developer-guide.md#how-do-i-enable-an-experimental-feature-on-my-origin).

The token must be present on both a) the page that uses the Speculation Rules API to trigger a prerender of a URL, and b) the target URL being prerendered.

**Example:**

On index.html:

```html
<meta http-equiv="origin-trial" content="**insert your token as provided in the developer console**">
<script type="speculationrules">
{
  "prerender": [
    {"source": "list", "urls": ["foo.html"]}
  ]
}
</script>
```

On foo.html:
```html
<meta http-equiv="origin-trial" content="**insert your token as provided in the developer console**">
<script>
if (document.prerendering)
  console.log("I am being prerendered!");

document.addEventListener('prerenderingchange', (event) => {
  console.log("I have been activated!");
});
</script>
```

In the above example, `index.html` provides a hint to the browser to prerender `foo.html`. The origin trial token is present on both pages.

## Debugging

There is limited debugging support for prerendering at this time. Chrome's DevTools has almost no knowledge of prerendered pages. But there are still some methods to debug, described below.

### How to tell if a prerender was started

The <chrome://process-internals> page provides a quick way to check if a prerendered page exists. Navigate to that page, and then to the "Frame Trees" section.

A list of all pages and frames in the browser are displayed.

While invisible, a prerendered page is associated with a tab (or "WebContents") in the browser: the tab that contained the speculation rule that initiated the prerender. The <chrome://process-internals> page describes the active page in each WebContents, and the prerendered page, if any.

TODO: Add screenshot.

The relevant information from the above screenshot is extracted below:

```
WebContents: https://prerender2-specrules.glitch.me, 1 active frame, 1 prerender root
    Frame[...]: url: https://prerender2-specrules.glitch.me/
    Frame[...]: prerender, url: https://prerender2-specrules.glitch.me/timer.html
```

This indicates that the tab contains one active page (rooted at <https://prerender2-specrules.glitch.me/>) and one prerendered page (rooted at <https://prerender2-specrules.glitch.me/timer.html>).

If there is no mention of "prerender root" on <chrome://process-internals#web-contents>, then there is currently no prerendering page.

Aside from this internal page, you may also find it convenient to use JavaScript to detect the prerendered page programmatically. Prerendered pages and active pages can use [Broadcast Channel](https://developer.mozilla.org/docs/Web/API/Broadcast_Channel_API) to communicate with each other.

**Example:**

On index.html:
```
<script type="speculationrules">
{
  "prerender": [
    {"source": "list", "urls": ["foo.html"]}
  ]
}
</script>
<script>
const bc = new BroadcastChannel('channel');
bc.addEventListener('message', e => {
  console.log(`received message: ${e.data}`);
});
</script>
```

On foo.html:
```
<script>
const bc = new BroadcastChannel('channel');
if (document.prerendering) {
  bc.postMessage(`prerender started for ${window.location.href}!`);
}
</script>
```

Upon successful prerender, index.html receives a message that foo.html is being prerendered.

### How to tell if a prerender was activated

After a navigation, you may want to check whether a prerendered page was activated, or if a new page load occurred.

One way to do this involves executing script in the DevTools Console. If DevTools was open prior to the navigation, you must **close and reopen DevTools** in order for it to see the activated page ([crbug](https://crbug.com/1170464)). Then in the console, check if `activationStart` is populated:

```javascript
let activationStart = performance.getEntriesByType('navigation')[0].activationStart;
console.log(activationStart);
```

The `activationStart` milestone is populated at the beginning of a navigation that activates a prerender, so a non-zero value means that the page was activated.

You can of course also do this programmatically by listening for the prerenderingchange event:

```javascript
let wasActivated = false;
document.addEventListener('prerenderingchange', (event) => {
  wasActivated = true;
});
```

Now `wasActivated` after navigating to the page indicates whether the page was activated.

### Using histograms

If the prerender is not started or not activated, it can admittedly be difficult to figure out why. As a last resort, checking Chrome's internal histograms may provide clues.

A prerender attempt is logged in the Prerender.Experimental.PrerenderHostFinalStatus histogram when it is eventually activated or discarded. You can view this histogram at chrome://histograms/Prerender.Experimental.PrerenderHostFinalStatus. A value of 0 is logged when a prerender is successfully activation; other values indicate prerenders that started and were discarded. A list as reasons as of August 2021 is available [here](https://source.chromium.org/chromium/chromium/src/+/main:content/browser/prerender/prerender_host.h;l=53;drc=d4099a80842a10144a7e678155667b4a84dc802f).

## Measuring performance

It is recommended to use real user monitoring (RUM) methods to measure the performance of the origin trial.

See the [Timing APIs](same-origin-explainer.md#timing-apis) section of the explainer for how to measure user-perceived durations.

## Chrome-specific behaviors and known issues

### Platforms

* Only Android Chrome is supported, and only for devices with 2GB+ of memory.
* Chrome on Desktop and Android WebView is not yet supported. The feature can be enabled locally on Desktop using chrome://flags and enabling Prerender2, but the origin trial is not supported.

### Speculation rules

A limited subset of the proposed Speculation Rules API is currently offered. Basically, the origin trial allows a document to trigger a single prerender.

In the typical case, a prerender lives as long as the document that triggered it is alive, until it is either activated by a subsequent navigation to the prerendered URL, or discarded due to a navigation to another URL.

In more detail:
* Only "prerender" actions are supported. The action "prefetch_with_subresources" is additionally supported in a [separate origin trial](https://developer.chrome.com/origintrials/#/view_trial/4576783121315266561) that requires its own token. It is acceptable to mix these origin trials.
* Only same-origin prerendering is permitted. Cross-origin redirects cause prerendering to be cancelled. Any navigation away from the initial prerendered page also cancels the prerendering (exception: same-document navigations are allowed).
* We only process rules being added; removal of rule sets is presently ignored.
* We only accept list rules.
* A page can only trigger a single prerender. Other hints are ignored.
* The `score` property has no effect. We prerender the first hint encountered.
* Documents in subframes cannot trigger a prerender.

### DevTools

* DevTools cannot inspect a currently prerendering page.
* DevTools must be closed and reopened in order to inspect an activated page ([crbug](https://crbug.com/1170464)).

### Prerendered page behaviors

Many powerful APIs are deferred in prerendering: they do not have an effect until after activation. Some behaviors and APIs cause a cancellation of the prerender, because Chrome does not yet handle deferring or handling them gracefully. The following is a non-exhaustive list of features that may cause a cancellation:
* Using WebAudio and generally attempting to playing media.
* Triggering a download with `<a download>` or the `Content-Disposition` header.
* Using the Gamepad API or Notifications API.
* Prerendering a page whose main document has a non-OK HTTP status code or that requires special handling due to client certificates, basic HTTP authentication, or SSL certification errors.
* Navigating the prerendered document to another document using `window.location`, `<meta http-equiv="refresh">`, etc. Same-document navigations are allowed.

### Activation eligibility

On a navigation, Chrome will only activate a prerendered page that was created in the same tab that the navigation is occurring in. To ensure the activation makes sense, Chrome checks that the navigation that created the prerendered page (the initial prerender navigation) is equivalent to the navigation that activates it. While the specification requires the URL and the referrer policy of the two navigations are equal, Chrome is more strict. In particular, properties such as the HTTP headers of the two navigations must be the same.

If the navigations differ, Chrome will elect to not activate the page, and it will be discarded as the navigation loads a page anew and destroys the document that triggered the prerender.

## Feedback

We would be happy to hear from you! Please direct feedback about the origin trial to <navigation-dev@chromium.org>. You may also file bugs [here](https://crbug.new). Describing the bug as related to the same-origin prerendering origin trial will help route it to the correct people. For feedback on the specification and the shape of the API, file issues at the [Prerendering, revamped](https://github.com/jeremyroman/alternate-loading-modes/issues) repository.

Thank you, and may your pages load instantly.
