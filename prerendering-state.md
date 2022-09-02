# Prerendering State API

## Summary

We propose introducing a boolean property `document.prerendering` and associated change event to distinguish
prerendering browsing contexts from regular ones.

_Note: This is based on the more general discussion in this [background
doc](https://docs.google.com/document/d/1Xzw0k8DgltI2ohapuDKmjRZLv7NVrRFGusW8IBtiCT0/edit?usp=sharing)._

## Background

Pages need to know when they're being rendered inside a [prerendering browsing context](https://wicg.github.io/nav-speculation/prerendering.html#prerendering-browsing-context).
Some examples of divergent behavior:

* Avoid fetching large video resources
* Avoid measuring ad impressions
* Avoid running JavaScript animations
* Avoid measuring user interactions for analytics
* Avoid starting server-coordinated behavior (e.g. ticket purchase countdown).

A previous iteration of prerendering used [page-visibility](https://w3c.github.io/page-visibility/) to denote a
prerendering context. However, this was unimplemented and [removed from the
specification](https://github.com/w3c/page-visibility/issues/42).

With the re-introduction of prererendering, we need to bring back some form of this API.

## Why not `visibilityState=='prerender'`?

The most straightforward way to do this would be to bring back the previously specified `document.visibilityState ==
'prerender'`.  Doing so has a number of drawbacks:

### Not mutually-exclusive

In actuality, some of the above use cases are interested in visibility rather than prerendering state.  For example, an
ordinary (i.e. non-prerendering) page that's hidden would likely want to "avoid running JavaScript animations" and
"avoid fetching large video resources". Thus, pages would have to consider both the `hidden` state as well as a
re-introduced `prerender` to get the desired behavior.

However, the [portals proposal](https://github.com/WICG/portals/) means that `prerender` isn't mutually exclusive
with `visible` either. In that case, we do want to "run JavaScript animations" and "fetch large resources" since it'll
be visible to the user, despite being in a prerendering browsing context (and all the restrictions that come with that).

### Web-compatibility

Related to the above point, a common pattern on the web is to assume only two visibility states. For example, code such
as:

```js
onload = () => {
  if (document.visibilityState == 'visible')
    // Load large images
  else
    // Defer loading large images
}
```

An analysis [found several
examples](https://docs.google.com/document/d/1Xzw0k8DgltI2ohapuDKmjRZLv7NVrRFGusW8IBtiCT0/edit#heading=h.rkorueof7xev)
of such behavior.

(re-)Introducing a `prerender` state could break such pages. In particular, portals (or some other, future
prerendering-while-visible context) would show static or missing content. A hidden prerender may not have immediate
user-visible effects, but may use more resources than necessary.

## `document.prerendering`

We propose adding a new state variable:

```webidl
partial interface Document {
    readonly attribute boolean    prerendering;
    attribute EventHandler        onprerenderingchange;
};
```

`document.prerendering` returns true if the document's top-level browsing context is a prerendering browsing
context. The `prerenderingchange` event is fired whenever this value changes.

A state separate from visibility ensures existing visibility-based states are correctly accounted for. It also forces
authors to consider their page's behavior in light of prerendering restrictions and non-interactivity and the fact that
a user may not have initiated the page load in the first place.

### Relationship to `visibilityState`

`prerendering` and `visibilityState` are entirely independent and all combinations of states are possible:

| State          | `prerendering` | `visibilityState` |
| -------------- | -------------- | ----------------- |
| Foreground Tab | false          | 'visible'         |
| Background Tab | false          | 'hidden'          |
| Portal         | true           | 'visible'         |
| Prerender      | true           | 'hidden'          |

### Relationship to BFCache

Some user agents provide a "Back-Forward" cache which keeps recent documents from the session history alive, enabling
instant history based navigations. While in the cache, these documents are typically put into a frozen state where
script cannot run and APIs and features with side-effects are blocked (e.g. camera, BroadcastMessage, etc.).

On the surface, this frozen state shares some resemblance with prerendering restrictions, which also aim to limit
visible side-effects and may, in some circumstances, completely freeze a page. It's likely that some of these mechanisms
will be shared between prerendering browsing contexts and BFCache implementations; however, we don't anticipate
BFCache'd documents to be put into a prerendering browsing context. As such, `document.prerendering` would not reflect a
BFCache'd state. The [Page Lifecycle APIs](https://wicg.github.io/page-lifecycle) remain relevant for this case.

## Open Questions

### `visibilityState` as a termination signal

Authors have been [encouraged](https://www.igvita.com/2015/11/20/dont-lose-user-and-app-state-use-page-visibility/) to
switch from `unload` and `beforeunload` events to `visibilityState=='hidden'` as a signal that their page may be
terminated. See also [w3c/PageVisibility#59](https://github.com/w3c/page-visibility/issues/59) for related discussion.

Entering a `prerendering` state by being put into a portal (via portal predecessor adoption), is likely a point where
such a termination signal should be fired; it is analogous to navigating to a new page. However, this means pages would
now also have to listen for a switch to `prerendering == true`.

This [background
doc](https://docs.google.com/document/d/1Xzw0k8DgltI2ohapuDKmjRZLv7NVrRFGusW8IBtiCT0/edit#heading=h.acmnp6zdmcik) deals
extensively with this issue. An ideal solution would introduce a new event for this use case, rather than implicitly
tying it to any particular state. In the near term, we don't think this is a critical use case to solve; when portals
develop closer to shipping, we can revisit whether adding such an event is necessary.

### Relationship to other states

As noted in the [background
doc](https://docs.google.com/document/d/1Xzw0k8DgltI2ohapuDKmjRZLv7NVrRFGusW8IBtiCT0/edit#heading=h.14z99pd6akf0), there
are other states where it may make sense to report `prerendering` state. For example, a page loading into a mobile
background tab maybe terminated, without notice, before the user ever sees it. Similarly, the live-preview in a mobile app
or tab switcher is a non-interactive preview, reminiscent of a portal.

Should these states also report `prerendering==true`? Should they use the prerendering browsing context concept? The
answers here aren't clear but this is worth considering.

### Naming bikeshed

We've called this state `prerendering` here to make clear the association between it and a prerendering browsing
context. However, this _may_ be misleading in some cases. Portals aren't exactly prerendering in the way most authors
would think about it. Additionally, a portal may enter the prerendering state from a regular context; this feels
unintuitive to call "prerendering".

We should also consider future use cases. For example, if
[fenced-frames](https://github.com/shivanigithub/fenced-frame/) were to use this special browsing context, does it make
sense to call it "prerendering"?

The term "interactive" seems appealing as it captures a major difference between prerendering/portals and regular
browsing contexts. However, it would be unintuitive to explain how a background tab is considered "interactive". In
particular, if we want this to solve [w3c/PageVisibility#59](https://github.com/w3c/page-visibility/issues/59) we'd have the
bizarre case that entering the app switcher would make a page non-interactive, then backgrounding it from there would make
it interactive.
