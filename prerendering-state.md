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

However, it's possible for there to be situations where a prerendered page is visible. Examples include the now-defunct [portals](https://github.com/WICG/portals/) proposal, or browser UI modes that prerender pages on hovering over or long-pressing links. In such cases, we do want to "run JavaScript animations" and "fetch large resources" since the page will be visible to the user, despite being in a prerendering browsing context (and all the restrictions that come with that).

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

`document.prerendering` returns true if the document's top-level browsing context is a prerendering browsing context. The `prerenderingchange` event is fired whenever this value changes. Currently, it is only ever possible for it to transition from true to false.

A state separate from visibility ensures existing visibility-based states are correctly accounted for. It also forces
authors to consider their page's behavior in light of prerendering restrictions and non-interactivity and the fact that
a user may not have initiated the page load in the first place.

### Relationship to `visibilityState`

`prerendering` and `visibilityState` are entirely independent and all combinations of states are possible:

| State                       | `prerendering` | `visibilityState` |
| --------------------------- | -------------- | ----------------- |
| Foreground tab              | false          | 'visible'         |
| Background tab              | false          | 'hidden'          |
| Browser UI page preview     | true           | 'visible'         |
| Speculation rules prerender | true           | 'hidden'          |

### Relationship to BFCache

Some user agents provide a "Back-Forward" cache which keeps recent documents from the session history alive, enabling
instant history based navigations. While in the cache, these documents are typically put into a frozen state where
script cannot run and APIs and features with side-effects are blocked (e.g. camera, BroadcastMessage, etc.).

On the surface, this frozen state shares some resemblance with prerendering restrictions, which also aim to limit
visible side-effects and may, in some circumstances, completely freeze a page. It's likely that some of these mechanisms
will be shared between prerendering browsing contexts and BFCache implementations; however, we don't anticipate
BFCache'd documents to be put into a prerendering browsing context. As such, `document.prerendering` would not reflect a
BFCache'd state. The [Page Lifecycle APIs](https://wicg.github.io/page-lifecycle) remain relevant for this case.
