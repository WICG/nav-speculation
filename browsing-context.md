# Prerendering browsing contexts

We envision modernized prerendering to work by loading content into a **prerendering browsing context**. A prerendering browsing context can be thought of as a tab that is not yet shown to the user, and which the user has not yet affirmatively indicated an intention to visit. As such, it has additional restrictions placed on it to ensure the user's privacy and prevent disruptions.

Prerendering browsing contexts can be _activated_, which causes them to transition to being full top-level browsing contexts (i.e. tabs). From a user experience perspective, activation acts like an instantaneous navigation, since unlike normal navigation it does not require a network round-trip, creation of a `Document`, or running of the web-developer-provided initialization JavaScript. All of that has already been done in the prerendering browsing context. Activation might replace an existing top-level browsing context, for example if the user clicks a normal link whose target has been prerendered. Or it might just cause the a new top-level browsing context to exist, for example if the user clicks on a `target="_blank"` link. Activation lifts the restrictions on the prerendered content, as by that point a user-visible navigation has occurred.

In general, activation of a prerendering browsing context is done by the user agent, when it notices a navigation that could use the prerendered contents. However, some forms of prerendering, such as [portals](https://github.com/WICG/portals/blob/master/README.md), can provide explicit entry points for navigation.

`Document`s rendered within a prerendering browsing context have the ability to react to activation, which they can use to upgrade themselves once free of the restrictions. For example, they could start using permission-requiring APIs, or get access to unpartitioned storage.

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
- [Session history](#session-history)
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

However, if `https://b.example/` is one of those sites that requests notification permissions on first load, such a permission prompt will be denied, as if the user had declined. (TODO or should it hang, as if the user refused to respond?) Similarly, if `https://b.example/` performs an `alert()` call, the call will instantly return, without the user seeing anything. Another key difference is that `https://b.example/` will not have any storage access, including to cookies. Thus, the content it initially renders will be a logged-out view of the web app, or perhaps a specially-tailed "prerendering" view which leaves things like logged-in state indeterminate.

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

A prerendering browsing context can contain either a same-site or cross-site resource. Same-site prerendered content don't present any privacy risks, but cross-site resources risk enabling [cross-site recognition](https://w3cping.github.io/privacy-threat-model/#model-cross-site-recognition) by creating a messaging channel across otherwise-partitioned domains. For simplicity, when a cross-site channel needs to be blocked, we also block it for same-site cross-origin content. In some cases we event block it for same-origin content.

Because prerendered browsing contexts can be activated, they (eventually) live in the first-party [storage shelf](https://storage.spec.whatwg.org/#storage-shelf) of their origin. This means that the usual plan of [storage partitioning](https://github.com/privacycg/storage-partitioning) does not suffice for prerendering browsing contexts as it does for nested browsing contexts (i.e. iframes). Instead, we take the following measures to restrict cross-origin prerendered content:

- Prevent communication with the referring document, to the same extent we prevent it with a cross-site link opened in a new tab.
- Block all storage access while content is prerendered.

If we allowed communication, then the prerendered content could be given the user ID from the host site. Then, after activation gives the prerendered page access to first-party storage, it would join that user ID with information from its own first-party storage to perform cross-site tracking.

If we allowed access to unpartitioned storage, then side channels available pre-activation (e.g., server-side timing correlation) could potentially be used to join two separate user identifiers, one from the referring site and one from the prerendered site's unpartitioned storage.

The below subsections explore the implementation of these restrictions in more detail.

#### Storage access blocking

Prerendered pages that are cross-origin to their referring site will have no access to storage, similar to how an opaque-origin `<iframe>` behaves. (See this [discussion on the spec mechanism](https://github.com/whatwg/storage/issues/18#issuecomment-615336554).)

We could attempt to address the threat by providing partitioned or ephemeral storage access, but then it is unclear how to transition to _unpartitioned_ storage upon activation. It would likely require some kind of web-developer-written merging logic. Completely blocking storage access is thus deemed simpler; prerendered pages should not be doing anything which requires persistent storage before activation.

This means that most existing content will appear "broken" when prerendered by a cross-origin referrer. This necessitates an explicit opt-in to allow cross-origin content to be prerendered, [discussed elsewhere](./opt-in.md). Such content might optionally "upgrade" itself to a credentialed view upon activation, as shown in the [example](#example) above.

For a more concrete example, consider `https://aggregator.example/` which wants to prerender this GitHub repository. To make this work, GitHub would need to add the opt-in to allow the page to be prerendered. Additionally, GitHub should add code to adapt their UI to show the logged-in view upon activation, by removing the "Join GitHub today" banner, and retrieving the user's credentials from storage and using them to replace the signed-out header with the signed-in header. Without such adapter code, activating the prerendering browsing context would show the user a logged-out view of GitHub in the top-level tab that the prerendering browsing context has been activated into. This would be a bad and confusing user experience, since the user is logged in to GitHub in all of their other top-level tabs.

#### Communications channels that are blocked

- Prerendering browsing contexts have no reference to the `Window`, or other objects, of their referrer. Thus, they cannot communicate using [`postMessage()`](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage) or other APIs.
- `BroadcastChannel` is disabled within prerendering browsing contexts.
- Fetches within cross-origin prerendering browsing contexts, including the initial request for the page, do not use credentials. Credentialed fetches could be used for cross-site recognition, for example by:
  - Using the sequence of loads. The referring page could encode a user ID into the order in which a sequence of URLs are prerendered. To prevent the target from correlating this ID with its own user ID without a navigation, a document loaded into a cross-origin prerendering browsing context is fetched without credentials and doesn't have access to storage, as described above.
  - The host creates a prerendering browsing context, and the prerendered site decides between a 204 and a real response based on the user's ID. Or the prerendered site delays the response by an amount of time that depends on the user's ID. Because the prerendering load is done without credentials, the prerendered site can't get its user ID in order to make this sort of decision.
- Sizing side channels: prerendering browsing contexts always perform layout based on the initial size of their referring browsing context, as its most likely that upon activation, they'll end up with that same size. However, further resizes to the referring browsing context are not used to update the size of the prerendering browsing context, as this could be used to communicate a user ID. For simplicity, this is the case for same-origin portals too.

#### Communications channels that match navigation

As mentioned above, we prevent communications to the same extent we prevent it with a cross-site link opened in a new tab. In particular:

- The prerendered content's own URL and the referring URL are available to prerendered content to the same extent they're available to normal navigations. Solutions to link decoration will apply to both.

Note that since a non-activated prerendering browsing context has no storage access, it cannot join any information stored in the URL with any of the prerendered site's data. So it's only activation, which gives full first-party storage access, which creates a navigation-equivalent communications channel. This equivalence makes sense, as activating a prerendering browsing context is much like clicking a link.

### Restrictions on the basis of being non-user-visible

Apart from the privacy-related restrictions to communications and storage, while prerendered, pages are additionally restricted in various ways due to the fact that the user has not yet expressed any intent to interact. All of these restrictions apply regardless of the same- or cross-origin status of the prerendered content.

- Any features that are controlled by the [Permissions API](https://w3c.github.io/permissions/) ([list](https://w3c.github.io/permissions/#permission-registry)) will be automatically denied without prompting. TODO or deferred until activation?

- Any features controlled by [Permissions Policy](https://w3c.github.io/webappsec-permissions-policy/) ([list](https://github.com/w3c/webappsec-permissions-policy/blob/master/features.md)) will be disabled, unless their default allowlist is `*`. There is no ability for the referring page to delegate these permissions. (In particular, there is no counterpart to `<iframe>`'s `allow=""` attribute.)

- Popups, pointer lock, orientation lock, the presentation API, downloads, and modal dialogs (`alert()` etc.) all are disabled pre-activation. (These are features which are currently only possible to disable with through [iframe sandboxing](https://html.spec.whatwg.org/multipage/origin.html#sandboxing).)

- Any feature which requires [user activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation) will not be available, since user activation is not possible in prerendering browsing contexts.

After activation, these restrictions are lifted: the content is treated like a normal top-level browsing context, and is able to use all these features in the normal way. The [API](#javascript-api) can be used to request permissions upon activation, if necessary. (Although doing so gives a user experience equivalent to requesting permissions on load, and thus is rarely the best design.)

_Note: ideally Permissions Policy would become a superset of the Permissions API and iframe sandboxing. Then we could use that infrastructure as the single place to impose and lift these restrictions. Currently that is not the case, so the spec will be more messy._

### Restrictions on loaded content

To simplify implementation, specification, and the web-developer facing consequences, prerendering browsing contexts cannot host non-HTTP(S) `Document`s. In particular, they cannot host:

- `javascript:` URLs
- `data:` URLs
- `blob:` URLs
- `about:` URLs, including `about:blank` and `about:srcdoc`

In some cases, supporting these would create a novel situation for a top-level browsing context: for example, right now, a top-level browsing context cannot navigate to a `data:` or `blob:` URL, so allowing those to be prerendered and then activated (which is equivalent to a navigation) would require new implementation and specification infrastructure.

In other cases, like `javascript:` URLs or `about:blank`, the problem is that those URLs generally inherit properties from their creator, and we don't want to allow this cross-`Document` influence for prerendered content. Overall, restricting to HTTP(S) URLs ensures that prerendered content always has a well-defined origin, that is not contingent on the referring page.

The removal of the script-visible `about:blank` in prerendering browsing contexts also greatly simplifies them; its existence in other browsing contexts causes `Window`s and `Document`s to lose their normally one-to-one relationship.

If a prerendering browsing context navigates itself to a non-HTTP(S) URL, e.g. via `window.location = "data:text/plain,foo"`, then the prerendering browsing context will be immediately discarded, and no longer be used by the user agent for anything.

## JavaScript API

We're still discussing various options for the API. Here we present the considerations in play, plus our our tentative idea. The latter is mostly so that examples in this and other documents have something to exhibit.

Goals:

- Allow prerendered content to know that it's prerendered.
- Allow prerendered content to know when it stops being prerendered.
- Play nicely with existing or related APIs such as [the storage access API](https://github.com/privacycg/storage-access/) or the [page visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API).

Nice-to-haves:

- Be general enough to accomodate other "alternate loading modes", such as prefetching or [fenced frames](https://github.com/shivanigithub/fenced-frame/)

### Current proposal

The current proposed API is a `document.loadingMode` object with:

- A property, `type`, which is either `"default"`, `"prerender"`, or `"uncredentialed-prerender"`. It could be extended in the future to other types.
- An event, `"change"`, which fires when `type` changes.

Envisioned usage is as follows:

```js
function afterPrerendering() {
  // grab user data from cookies/IndexedDB
  // ask for a bunch of permission-requiring features
  // do some alert()s and
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

Finally, there's the case of the [page visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API). Our current plan is to treat prerendering browsing contexts as hidden, until activation, in which case code that only wants to run upon the user viewing the page could be done as follows:

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

_An alternative is to reintroduce the `"prerender"` visibility state, which was briefly specified, but never implemented. However, we worry that this would break code like the above, which assumes that there are only two visibility states in existence._

## Session history

From the user's perspective, activating a prerendering browsing context behaves like a conventional navigation. The current `Document` displayed in the prerendering browsing context is appended to session history, with any existing forward history entries pruned. Any navigations which took place within the prerendering browsing context, before activation, do not affect session history.

From the developer's perspective, a prerendering browsing context can be thought of as having a trivial [session history](https://html.spec.whatwg.org/multipage/history.html#the-session-history-of-browsing-contexts) where only one entry, the current entry, exists. All navigations within the prerendering browsing context are effectively done with replacement. While APIs that operate on session history, such as [window.history](https://html.spec.whatwg.org/multipage/history.html#the-history-interface), can be called within prerendering browsing contexts, they only operate on the context's trivial session history. Consequently, prerendering browsing contexts do not take part in their referring page's joint session history; that is, they cannot navigate their referrer by calling `history.back()` enough times, like iframes can navigate their embedders.

This model ensures that users get the expected experience when using the back button, i.e., that they are taken back to the last thing they saw. Once a prerendering browsing context is activated, only a single session history entry gets appended to the joint session history, ignoring any previous navigations that happened within the prerendering browsing context. Then, stepping back one step in the joint session history, e.g. by pressing the back button, takes the user back to the referrer page.

## Rendering-related behavior

Prerendered content needs to strike a delicate balance, of doing enough rendering to be useful, but not actually displaying any pixels on the user's screen. As such, we want developers to avoid performing expensive work which is not beneficial while being prerendered. And ideally, doing this should require minimal additional coding by the developer of the page being prerendered.

Generally speaking, our plan is to treat content as if it were in a "background tab": it will still perform layout, using (for [privacy and simplicity reasons](#communications-channels-that-are-blocked)) the creation-time size of the referring page as the viewport. Rendering APIs which communicate visibility information, such as [Intersection Observer](https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API) or the [`loading` attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-loading), will indicate that no content is in the viewport. (TODO is this right, or should the initial screenful be counted as in the viewport? How does it compare to background tabs?)

## CSP integration

A prerendered `Document` can apply CSP to itself as normal. Being in a prerendering browsing context vs. a normal top-level browsing context does not change any of the impacts of CSP. Note that since prerendered documents are [always loaded from HTTP(S) URLs](#restrictions-on-loaded-content), there is no need to worry about complex CSP inheritance semantics.

Prerendered content will be affected by [`prefetch-src`](https://w3c.github.io/webappsec-csp/#directive-prefetch-src) on the referring page, which provides a way of preventing prefetching in addition to the [triggers](./triggers.md).

The [`navigate-to`](https://w3c.github.io/webappsec-csp/#directive-navigate-to) directive prevents navigations, which means that if prerendered content is prevented from being navigated to via this mechanism, then the corresponding prerendering browsing context will never be activated. This mostly falls out automatically from the CSP spec preventing navigations, but any prerendering APIs that explicitly expose the activation operation (such as [portals](https://github.com/WICG/portals/blob/master/README.md)) will need to account for it in their specification.
