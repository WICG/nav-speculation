# Prerendering browsing contexts

We envision modernized prerendering to work by loading content into a **prerendering browsing context**, which is a new type of [top-level browsing context](https://html.spec.whatwg.org/multipage/browsers.html#top-level-browsing-context). A prerendering browsing context can be thought of as a tab that is not yet shown to the user, and which the user has not yet affirmatively indicated an intention to visit. As such, it has additional restrictions placed on it to ensure the user's privacy and prevent disruptions.

Prerendering browsing contexts can be _activated_, which causes them to transition to being full top-level browsing contexts (i.e. tabs). From a user experience perspective, activation acts like an instantaneous navigation, since unlike normal navigation it does not require a network round-trip, creation of a `Document`, or running of the web-developer-provided initialization JavaScript. All of that has already been done in the prerendering browsing context. (Or at least, the majority of it; the site might delay some of its initialization until activation, or some of the initialization might not have finished, especially if the browser deprioritizes unactivated browsing contexts.)

Activation might replace an existing top-level browsing context, for example if the user clicks a normal link whose target has been prerendered. Or it might cause the prerendered context to be shown in a new tab/window, for example if the user clicks on a `target="_blank"` link. Activation lifts the restrictions on the prerendered content, as by that point a user-visible navigation has occurred.

In general, activation of a prerendering browsing context is done by the user agent, when it notices a navigation that could use the prerendered contents. However, some forms of prerendering, such as [portals](https://github.com/WICG/portals/blob/master/README.md), can provide explicit entry points for activation.

Documents rendered within a prerendering browsing context have the ability to react to activation, which they can use to upgrade themselves once free of the restrictions. For example, they could start using permission-requiring APIs, or get access to unpartitioned storage.

_Note: a browsing context is the right primitive here, as opposed to a `Window` or `Document`, as we need these restrictions to apply even across navigations. For example, if you prerender `https://a.example/` which contains `<meta http-equiv="refresh" content="0; URL=https://a.example/home">` then we need to continue applying these restrictions while loading the `/home` page._

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of contents

- [Example](#example)
- [Restrictions](#restrictions)
  - [Privacy-based restrictions](#privacy-based-restrictions)
    - [Storage access blocking](#storage-access-blocking)
    - [Communications channels that are blocked](#communications-channels-that-are-blocked)
    - [Communications channels that match navigation](#communications-channels-that-match-navigation)
  - [Restrictions on the basis of being non-user-visible](#restrictions-on-the-basis-of-being-non-user-visible)
  - [Restrictions on loaded content](#restrictions-on-loaded-content)
- [JavaScript API](#javascript-api)
  - [Current proposal](#current-proposal)
  - [Adjacent APIs](#adjacent-apis)
- [Page lifecycle and freezing](#page-lifecycle-and-freezing)
- [Session history](#session-history)
- [Navigation](#navigation)
- [Rendering-related behavior](#rendering-related-behavior)
- [CSP integration](#csp-integration)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Example

Consider `https://a.example/`, which contains the following HTML:

```html
<link rel="prerender2" href="https://b.example/">

<a href="https://b.example/">Click me!</a>
```

_The `"prerender2"` rel here is illustrative only. See the [triggers document](./triggers.md) for more serious discussion of potential APIs for triggering prerendering._

Upon loading `https://a.example/`, the browser notices the request to prerender `https://b.example/`. It does so by creating a prerendering browsing context, which it navigates to `https://b.example/`. This navigation takes place using [special fetch modes](./fetch.md), which ensure that `https://b.example/` has [opted in](./opt-in.md) to being prerendered, and ensures that the request for `https://b.example/` and any of its subresources is performed without any credentials that might identify the user.

Within this prerendering browsing context, assuming the opt-in check passes, loading of `https://b.example/` proceeds mostly as normal. This includes any expensive web-developer-provided JavaScript necessary to initialize the web app found there. It could even include server- or client-side redirects to other pages, perhaps even other domains.

However, if `https://b.example/` is one of those sites that requests notification permissions on first load, such a permission prompt will be denied, as if the user had declined. Similarly, if `https://b.example/` performs an `alert()` call, the call will instantly return, without the user seeing anything. Another key difference is that `https://b.example/` will not have any storage access, including to cookies. Thus, the content it initially renders will be a logged-out view of the web app, or perhaps a specially-tailored "prerendering" view which leaves things like logged-in state indeterminate.

(The above describes a conservative plan for the behavior restrictions of prerendered content. See also [#7](https://github.com/jeremyroman/alternate-loading-modes/issues/7) and [#8](https://github.com/jeremyroman/alternate-loading-modes/issues/8) for discussion of alternate strategies.)

Now, the user clicks on the "Click me!" link. At this point the user agent notices that it has a prerendering browsing context originally created for `https://b.example/`, so it activates it, replacing the one displaying `https://a.example/`. The user observes their browser navigating to `https://b.example/`, e.g., via changes in the URL bar contents and the back/forward UI. And since `https://b.example/` was already loaded in the prerendering browsing context, this navigation occurs seamlessly and instantly, providing a great user experience.

Upon activation, `https://b.example/` gets notified via [the API](#javascript-api). At this point, it now has access to storage and cookies, so it can upgrade itself to a logged-in view if appropriate:

```js
document.loadingMode.addEventListener('change', () => {
    if (document.loadingMode.type === 'default') {
        document.getElementById('user').textContent = localStorage.getItem('current-user');
    }
});
```

This completes the journey to a fully-rendered view of `https://b.example/`, in a user-visible top-level browsing context.

## Restrictions

### Privacy-based restrictions

Prerendering is intended to comply with the [W3C Target Privacy Threat Model](https://w3cping.github.io/privacy-threat-model/). This section discusses the aspects of that threat model that are particularly relevant to the browsing context part of the story, and how the design satisfies them.

A prerendering browsing context can contain either a same-site or cross-site resource. Same-site prerendered content don't present any privacy risks, but cross-site resources risk enabling [cross-site recognition](https://w3cping.github.io/privacy-threat-model/#model-cross-site-recognition) by creating a messaging channel across otherwise-partitioned domains. For simplicity, when a cross-site channel needs to be blocked, we also block it for same-site cross-origin content. In some cases we even block it for same-origin content.

Because prerendered browsing contexts can be activated, they (eventually) live in the first-party [storage shelf](https://storage.spec.whatwg.org/#storage-shelf) of their origin. This means that the usual plan of [storage partitioning](https://github.com/privacycg/storage-partitioning) does not suffice for prerendering browsing contexts as it does for nested browsing contexts (i.e. iframes). Instead, we take the following measures to restrict cross-origin prerendered content:

- Prevent communication with the referring document, to the same extent we prevent it with a cross-site link opened in a new tab.
- Block all storage access while content is prerendered.

If we allowed communication, then the prerendered content could be given the user ID from the host site. Then, after activation gives the prerendered page access to first-party storage, it would join that user ID with information from its own first-party storage to perform cross-site tracking.

If we allowed access to (unpartitioned) storage, then side channels available pre-activation (e.g., server-side timing correlation) could potentially be used to join two separate user identifiers, one from the referring site and one from the prerendered site's unpartitioned storage.

The below subsections explore the implementation of these restrictions in more detail.

#### Storage access blocking

Prerendered pages that are cross-origin to their referring site will have no access to storage, similar to how an opaque-origin `<iframe>` behaves. (See this [discussion on the spec mechanism](https://github.com/whatwg/storage/issues/18#issuecomment-615336554).)

We could attempt to address the threat by providing partitioned or ephemeral storage access, but then it is unclear how to transition to _unpartitioned_ storage upon activation. It would likely require some kind of web-developer-written merging logic. Completely blocking storage access is thus deemed simpler; prerendered pages should not be doing anything which requires persistent storage before activation.

This means that most existing content will appear "broken" when prerendered by a cross-origin referrer. This necessitates an explicit opt-in to allow cross-origin content to be prerendered, [discussed elsewhere](./opt-in.md). Such content might optionally "upgrade" itself to a credentialed view upon activation, as shown in the [example](#example) above.

For a more concrete example, consider `https://aggregator.example/` which wants to prerender this GitHub repository. To make this work, GitHub would need to add the opt-in to allow the page to be prerendered. Additionally, GitHub should add code to adapt their UI to show the logged-in view upon activation, by removing the "Join GitHub today" banner, and retrieving the user's credentials from storage and using them to replace the signed-out header with the signed-in header. Without such adapter code, activating the prerendering browsing context would show the user a logged-out view of GitHub in the top-level tab that the prerendering browsing context has been activated into. This would be a bad and confusing user experience, since the user is logged in to GitHub in all of their other top-level tabs.

Exactly how storage access is blocked is still under discussion, in [#7](https://github.com/jeremyroman/alternate-loading-modes/issues/7). In particular, asynchronous storage operations could either immediately fail, or they could hang until activation, at which point they might succeed. And, for simpler types of storage such as cookies, it might be possible to do a merge from partitioned to unpartitioned storage, so we might want to explore partition-merging alternatives to full blocking.

#### Communications channels that are blocked

- Prerendering browsing contexts have no reference to the `Window`, or other objects, of their referrer. Thus, they cannot communicate using [`postMessage()`](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage) or other APIs.
- `BroadcastChannel` is disabled within prerendering browsing contexts.
- TODO service/shared workers?
- Fetches within cross-origin prerendering browsing contexts, including the initial request for the page, do not use credentials. Credentialed fetches could be used for cross-site recognition, for example by:
  - Using the sequence of loads. The referring page could encode a user ID into the order in which a sequence of URLs are prerendered. To prevent the target from correlating this ID with its own user ID without a navigation, a document loaded into a cross-origin prerendering browsing context is fetched without credentials and doesn't have access to storage, as described above.
  - The host creates a prerendering browsing context, and the prerendered site decides between a 204 and a real response based on the user's ID. Or the prerendered site delays the response by an amount of time that depends on the user's ID. Because the prerendering load is done without credentials, the prerendered site can't get its user ID in order to make this sort of decision.
- Sizing side channels: prerendering browsing contexts always perform layout based on the initial size of their referring browsing context, as its most likely that upon activation, they'll end up with that same size. However, further resizes to the referring browsing context are not used to update the size of the prerendering browsing context, as this could be used to communicate a user ID. For simplicity, we apply this sizing model to same-origin prerendered content as well.

#### Communications channels that match navigation

As mentioned above, we prevent communications to the same extent we prevent it with a cross-site link opened in a new tab. In particular:

- The prerendered content's own URL and the referring URL are available to prerendered content to the same extent they're available to normal navigations. Solutions to link decoration will apply to both.

Note that since a non-activated prerendering browsing context has no storage access, it cannot join any information stored in the URL with any of the prerendered site's data. So it's only activation, which gives full first-party storage access, which creates a navigation-equivalent communications channel. This equivalence makes sense, as activating a prerendering browsing context is much like clicking a link.

### Restrictions on the basis of being non-user-visible

Apart from the privacy-related restrictions to communications and storage, while prerendered, pages are additionally restricted in various ways due to the fact that the user has not yet expressed any intent to interact. All of these restrictions apply regardless of the same- or cross-origin status of the prerendered content.

Our initial proposal is that these APIs all be uniformly disabled, in the following manner. However, [#8](https://github.com/jeremyroman/alternate-loading-modes/issues/8) explores alternatives, where some of them have their effects delayed. We'll be experimenting with this during the prototyping phase.

- Any features that are controlled by the [Permissions API](https://w3c.github.io/permissions/) ([list](https://w3c.github.io/permissions/#permission-registry)) will be automatically denied without prompting.

- Any features controlled by [Permissions Policy](https://w3c.github.io/webappsec-permissions-policy/) ([list](https://github.com/w3c/webappsec-permissions-policy/blob/master/features.md)) will be disabled, unless their default allowlist is `*`. There is no ability for the referring page to delegate these permissions. (In particular, there is no counterpart to `<iframe>`'s `allow=""` attribute.)

- Popups, pointer lock, orientation lock, the presentation API, downloads, and modal dialogs (`alert()` etc.) all are disabled pre-activation. (These are features which are currently only possible to disable with through [iframe sandboxing](https://html.spec.whatwg.org/multipage/origin.html#sandboxing).)

- Any feature which requires [user activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation) will not be available, since user activation is not possible in prerendering browsing contexts.

After activation, these restrictions are lifted: the content is treated like a normal top-level browsing context, and is able to use all these features in the normal way. The [API](#javascript-api) can be used to request permissions upon activation, if necessary. (Although doing so gives a user experience equivalent to requesting permissions on load, and thus is rarely the best design.)

_Note: ideally Permissions Policy would become a superset of the Permissions API and iframe sandboxing. Then we could use that infrastructure as the single place to impose and lift these restrictions. Currently that is not the case, so the spec will be more messy._

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

## JavaScript API

We're still discussing various options for the API; please join that discussion in [#2](https://github.com/jeremyroman/alternate-loading-modes/issues/2). Here we present the considerations in play, plus our our tentative idea. The latter is mostly so that examples in this and other documents have something to exhibit.

Goals:

- Allow prerendered content to know that it's prerendered.
- Allow prerendered content to know when it stops being prerendered.
- Play nicely with existing or related APIs such as [the storage access API](https://github.com/privacycg/storage-access/) or the [page visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API).

Nice-to-haves:

- Be general enough to accommodate other "alternate loading modes", such as [fenced frames](https://github.com/shivanigithub/fenced-frame/)

### Current proposal

The current proposed API is a `document.loadingMode` object with:

- A property, `type`, which is either `"default"`, `"prerender"`, or `"uncredentialed-prerender"`. It could be extended in the future to other types.
- An event, `"change"`, which fires when `type` changes.

Envisioned usage is as follows:

TODO: This example would likely want to use `document.prerendering` - even with `document.prerendering`, additional loading-mode information may still be useful for specialized cases where fetching may need to depend on the exact loading mode, can we find any examples/use cases? `document.prerendering` will likely cover the most common use cases without getting into the level of granularity of fetching restrictions.

```js
function afterPrerendering() {
  // grab user data from cookies/IndexedDB
  // ask for a bunch of permission-requiring features
  // do some alert()s
}

if (!document.loadingMode || document.loadingMode.type === 'default') {
    afterPrerendering();
} else {
    document.loadingMode.addEventListener('change', () => {
        if (document.loadingMode.type === 'default') {
            afterPrerendering();
        }
    });
}
```

In the future, `document.loadingMode` might have additional properties; for example, it might expose the notion that the page was loaded via some proxy, as mentioned in the [fetch integration](./fetch.md).

For exposing the semantic notion of prerendering (i.e. the user didn't initiate the load, the page is not interactive), we propose `document.prerendering`:

```js
if (document.prerendering) {
    afterPrerendering();
} else {
    document.onprerenderingchange = afterPrerendering;
}
```

Note: it's possible that `document.prerendering` may be  just syntactic sugar for some subset of `document.loadingMode.type`, e.g. `document.loadingMode.type != 'default'` or `document.loadingMode.type == 'prerender' || document.loadingMode.type == 'uncredentialed-prerender'`.

See [prerendering-state](prerendering-state.md) for more details.

### Adjacent APIs

In addition to the loading mode API proposed above, script can use APIs particular to the behavior they are interested in. For example, the [storage access API](https://github.com/privacycg/storage-access) API can be used in supporting browsers to observe whether unpartitioned storage is available. Especially with [a proposed extension](https://github.com/privacycg/storage-access/issues/55), this can be quite ergonomic:

```js
document.storageAccessAvailable.then(() => {
  // grab user data from cookies/IndexedDB
  // update the UI
});
```

Another similar case is asking for permissions. For this, the [Permissions API](https://developer.mozilla.org/en-US/docs/Web/API/Permissions_API) can be helpful:

```js
const geoPermission = await navigator.permissions.query("geolocation");
if (geoPermission.state === "denied") {
    geoPermission.onchange = () => {
        if (geoPermission.state === "prompt") {
            promptForGeolocation();
        }
    };
}
```

_Note: the above code only makes sense if we decide that permissions are denied in prerendering browsing contexts, instead of having them hang until activation. [That plan](#restrictions-on-the-basis-of-being-non-user-visible) is still tentative._

Finally, there's the case of the [page visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API). Our current plan is to treat (non-portal) prerendering browsing contexts as hidden, until activation, in which case code that only wants to run upon the user viewing the page could be done as follows:

```js
if (document.visibilityState === "visible") {
    videoElement.play();
}

document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
        videoElement.pause();
    } else {
        // visibilityState is "visible"
        videoElement.play();
    }
});
```

## Page lifecycle and freezing

User agents need to strike a delicate balance with prerendered content. Such content needs enough resources to do its initial setup work, so that loading it is as instant as possible. But it shouldn't consume resources in a way that would detract from a user's experience on the content they're actively viewing on the referring site.

One mechanism user agents will probably use for this is to freeze prerendered pages, in the sense defined by the [Page Lifecycle](https://wicg.github.io/page-lifecycle/) specification. The most important impact of freezing, for our purposes, is that tasks queued by the page will not be run by the event loop. In particular, we envision user agents freezing prerendered pages after some initial setup time, to avoid recurring timers or data transfers.

Another case where freezing might be useful is if the prerendered content performs some prohibited operation. As discussed in [#7](https://github.com/jeremyroman/alternate-loading-modes/issues/7) and [#8](https://github.com/jeremyroman/alternate-loading-modes/issues/8), we might make this part of the specified mechanism for enforcing the [restrictions](#restrictions) on prerendered content.

Using the freezing mechanism is a natural fit for prerendered content, since freezing is already performed by user agents for backgrounded content. In particular, content which uses the page lifecycle API (such as the `freeze` and `resume` events) will likely react correctly if it becomes frozen in a prerendering browsing context, just like if it were frozen in any other browsing context.

## Session history

From the user's perspective, activating a prerendering browsing context behaves like a conventional navigation. The current `Document` displayed in the prerendering browsing context is appended to session history, with any existing forward history entries pruned. Any navigations which took place within the prerendering browsing context, before activation, do not affect session history.

From the developer's perspective, a prerendering browsing context can be thought of as having a trivial [session history](https://html.spec.whatwg.org/multipage/history.html#the-session-history-of-browsing-contexts) where only one entry, the current entry, exists. All navigations within the prerendering browsing context are effectively done with replacement. While APIs that operate on session history, such as [window.history](https://html.spec.whatwg.org/multipage/history.html#the-history-interface), can be called within prerendering browsing contexts, they only operate on the context's trivial session history. Consequently, prerendering browsing contexts do not take part in their referring page's joint session history; that is, they cannot navigate their referrer by calling `history.back()` enough times, like iframes can navigate their embedders.

This model ensures that users get the expected experience when using the back button, i.e., that they are taken back to the last thing they saw. Once a prerendering browsing context is activated, only a single session history entry gets appended to the joint session history, ignoring any previous navigations that happened within the prerendering browsing context. Then, stepping back one step in the joint session history, e.g. by pressing the back button, takes the user back to the referrer page.

## Navigation

Each prerendering browsing context has an _original URL_, which is the URL it was originally instantiated with. For example, given

```html
<link rel="prerender2" href="https://a.example/">
```

the original URL is `https://a.example/`. Once instantiated, the prerendering browsing context might navigate elsewhere, e.g. via server-side redirects, `<meta http-equiv="refresh">`, or calling `.click()` on an `<a>` element. This will perform further with-replacement navigations within the prerendering browsing context, all offscreen. But the original URL stays the same.

Later, the prerendering browsing context can be used to satisfy a navigation, _based on the original URL_, not the prerendering browsing context's current URL. That is, if `https://a.example/` redirects to `https://b.example/`, then given

```html
<a href="https://a.example/">Click me!</a>
<a href="https://b.example/">Click me!</a>
```

only the navigation initiated by clicking on the first of these links could be satisfied by activating the prerendering browsing context.

Another interesting situation to consider is what happens if the user right-clicks on the first link, and chooses "Open in New Tab". The first time they do this, the new tab can be created instantly, by activating the prerendering browsing context. However, if they do it a second time, the prerendering browsing context has been used up; the second navigation will perform a normal, non-instant navigation.

## Rendering-related behavior

Prerendered content needs to strike a delicate balance, of doing enough rendering to be useful, but not actually displaying any pixels on the user's screen. As such, we want developers to avoid performing expensive work which is not beneficial while being prerendered. And ideally, doing this should require minimal additional coding by the developer of the page being prerendered.

Generally speaking, our plan is to treat content as if it were in a "background tab": it will still perform layout, using (for [privacy and simplicity reasons](#communications-channels-that-are-blocked)) the creation-time size of the referring page as the viewport. Rendering APIs which communicate visibility information, such as [Intersection Observer](https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API) or the [`loading` attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-loading), will indicate visibility based on the creation-time viewport.

## CSP integration

A prerendered `Document` can apply CSP to itself as normal. Being in a prerendering browsing context vs. a normal top-level browsing context does not change any of the impacts of CSP. Note that since prerendered documents are [always loaded from HTTP(S) URLs](#restrictions-on-loaded-content), there is no need to worry about complex CSP inheritance semantics.

Prerendered content will be affected by [`prefetch-src`](https://w3c.github.io/webappsec-csp/#directive-prefetch-src) on the referring page, which provides a way of preventing prefetching in addition to the [triggers](./triggers.md).

The [`navigate-to`](https://w3c.github.io/webappsec-csp/#directive-navigate-to) directive prevents navigations, which means that if prerendered content is prevented from being navigated to via this mechanism, then the corresponding prerendering browsing context will never be activated. This mostly falls out automatically from the CSP spec preventing navigations, but any prerendering APIs that explicitly expose the activation operation (such as [portals](https://github.com/WICG/portals/blob/master/README.md)) will need to account for it in their specification.

Note that `navigate-to` will prohibit navigations based on the URL of the link clicked (or similar), which corresponds to a prerendering browsing context's original URL (discussed [above](#navigation)). This means that given something like

```http
Content-Security-Policy: navigate-to https://a.example
```

and markup such as

```html
<link rel="prerender2" href="https://a.example/redirects-to-another-origin">

<script>
location.href = 'https://a.example/redirects-to-another-origin';
</script>
```

then the navigation will be allowed, _even though_ the prerendering browsing context could be pointing to an origin besides `https://a.example`. In other words, prerendering does not change the behavior of `navigate-to`, despite allowing the browser to know more information about the eventual navigation destination.
