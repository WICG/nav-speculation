# Prerendering, revamped

In order to making the experience of loading on the web faster, user agents employ prefetching and prerendering techniques. However, they have historically been [underspecified](https://w3c.github.io/resource-hints/#prerender) and [inconsistently implemented](https://caniuse.com/link-rel-prerender).

The space is full of challenges which have not been comprehensively tackled: most notably,

* avoiding user-visible side effects and annoyances from running script on the destination site; and
* fulfilling the privacy objectives of the user and the referring site.

This repository contains a set of explainers and (eventually) specifications which, combined, give a rigorous model for performing such prerendering of content, in an interoperably-implementable way. Each piece is designed to be composable and reusable; for example, [some contribute to prefetching](#prefetching), independent of prerendering, and the [opt-in](./opt-in.md) is designed to be usable by other types of alternate loading modes, such as [fenced frames](https://github.com/shivanigithub/fenced-frame/).

## Pieces of the solution

We envision prerendering having several related pieces:

* [**Prerender triggers**](./triggers.md), where a referring site indicates to the user agent what content can or should be prerendered.

  Today, we have the underspecified `<link rel="prerender">` element to provide these indications. Although something like this (probably with a different name, to avoid compatibility issues?) might be a good starting point, there are other points in the design space worth considering. For example, allowing the referring site to provide more blanket permission to prerender lets the user agent use its own heuristics.

* [**Prerendered content opt-in**](./opt-in.md), which allows pages to opt in to being prerendered by other cross-origin pages.

  In order to preserve privacy and avoid side effects, user agents need to prefetch content in a way that avoids identifying the user (e.g., omitting credentials). However, this means the response document cannot be personalized for the user. Pages need to indicate that they are prepared for this eventuality, and will "upgrade" themselves to personalization when they transition from prerendered to active.

* [**Prerendering fetching modes**](./fetch.md), which modify the way in which cross-origin documents and subresources are fetched in order to preserve privacy and avoid side effects.

  Closely related to the previous bullet, this covers the mechanics of how a document is fetched in order to check for the opt-in, and provide it with no identifying information. The most obvious technique here is omitting credentials, but others could include using a proxy server (for IP privacy), or using a previously-fetched response in "memory cache".

* [**Prerendering browsing contexts**](./browsing-context.md), which are special browsing contexts that are not displayed to the user, and within which content is constrained to not perform disruptive or side-effecting operations.

  In all prerendering browsing contexts, side-effecting or disruptive APIs, such as those that could play media, require a permission prompt, or otherwise display UI, will automatically error or no-op. In those tagged as being used for cross-origin prerendering, storage access will not be available (or, perhaps, is partitioned?), and all fetches will need to use the prerendering fetching modes.

  Crucially, prerendering browsing contexts have the ability to transition to becoming normal top-level browsing contexts, so that all of the prerendered content is reused and immediately displayed to the user.

* [**Portals**](https://github.com/WICG/portals/blob/master/README.md), which are a specialization of prerendering browsing contexts which can display a preview of the prerendered content to the user, and which expose a JavaScript API for transitioning to a normal top-level browsing context.

Each of these pieces is connected in various ways. However, we think they're decoupled enough that we will start by developing them as separate explainers and spec documents, cross-linking to each other as appropriate. It's also possible to implement only a subset of these, if a user agent is only interested in certain [scenarios](#example-scenarios).

## Same-origin vs. cross-origin prerendering

When prerendering same-origin content, many fewer constraints are necessary. Because there is no privacy concern, we can use normal fetching modes, and thus do not need an opt-in from the prerendered page. And the prerendering browsing context becomes simpler. Thus, the majority of work for specifying same-origin prerendering is in the prerendering triggers, the restrictions on disruptive APIs, and the transition to a normal top-level browsing context.

This simplicity benefits web developers as well, as they don't need to do the upgrade-from-uncredentialed dance which is necessary in cross-origin cases.

The tradeoff is that we now require opt-in from the referring page. The user agent cannot just heuristically prefetch or prerender any same-origin links that it sees; doing so would have bad consequences for links like `<a href="/logout">`.

Cross-origin prerendering, on the other hand, can be done without such triggers, because it is so much more constrained and requires opt-in from the content itself. The tradeoff is that, until the ecosystem starts preparing itself for prerendering via the opt-in and associated upgrade code, such prerenders are unlikely to succeed.

Here's a summary:

|                          |Opt-in location  |Restrictions on disruptive APIs |Restrictions on credentials/storage/etc. |
|--------------------------|-----------------|--------------------------------|-----------------------------------------|
|Same-origin prerendering  |Referring page   |Yes                             |No                                       |
|Cross-origin prerendering |Destination page |Yes                             |Yes                                      |

_Aside: it's probably safe to also allow same-origin prerendering with only a destination-side opt-in, as long as all of the same restrictions are applied (e.g., no credentials or storage access). But, this complicates the model a good deal, for both implementers and web developers. For now, we're concentrating on the model described above._

Finally, we'll note that browser-initiated prerenders fall somewhere in between these cases. In particular, the user typing `https://example.com/` in the URL bar, even before they press <kbd>Enter</kbd>, might serve as a reasonable prerender trigger, and perhaps even the prerendering could be done with credentials. The need to prevent user annoyance is still present, so the prerendering browsing context concept is important. But, what if the user types `https://example.com/logout`? Our thinking is still evolving in this area.

## Prefetching

Although these explainers focus largely on prerendering, we expect some of the work they produce to be useful for _prefetching_ as well. Prefetching currently exists in [`<link rel="prefetch">`](https://w3c.github.io/resource-hints/#dfn-prefetch), but as with prerendering, it is underspecified, and its current implementations have potential privacy issues for cross-origin prefetching, which will require some work to address.

In particular, the [triggers](./triggers.md) and [opt-in](./opt-in.md) can be designed in a generic way, so that they can also be used to trigger and opt-in to prefetching (of documents, in particular). Similarly, the [prerendering fetching infrastructure](./fetch.md) will likely be used for modernized prefetching.

## Example scenarios

### Same-origin drop-in speedup

One of the simplest things a web developer can do is indicate that their site is prepared for the browser to prerender most or all of its content. They would put something like the following in their `<head>`:

```html
<script type="speculationrules">
{
  "allow": [
    {
      "action": "prerender",
      "url_patterns": ["/**"]
    }
  ],
  "disallow": [
    {
      "action": "prefetch",
      "urls": ["/logout"]
    }
  ]
}
</script>
```

This indicates to the browser that all of the links it sees, except for any to `/logout`, are safe to prerender and prefetch. The browser can then heuristically perform such prerendering or prefetching when it has spare resources (bandwidth, CPU cycles, memory, ...). The browser could use any triggers it wanted for these heuristics, such as:

* Historical data from the current user
* Historical data aggregated over many users via telemetry
* Behavior patterns for similar sites (e.g., often users click on one of the top N product listings/comments links)
* Just-in-time behavior patterns (e.g., mouse hover)

This can be supplemented via per-page tweaks to increase the strength of the suggestion. For example, the `<script>` block could have

```json
{
  "action": "prerender",
  "selectors": [".high-likelihood-prerender"],
  "likelihood": "high"
}
```

and then decorate certain `<a>` elements with `class="high-likelihood-prerender"`.

When the browser performs this prerendering, it loads the same-origin document in a same-origin prerendering browsing context. Content there is not allowed to do disruptive, user-visible things, but it has full access to credentials, storage, etc.

### Cross-origin news aggregator

Consider a news aggregator website, which contains many links to different origins providing news articles.

Some such news providers might be prepared to be prerendered. To do so, they would opt in with the HTTP response header

```http
Supports-Loading-Mode: uncredentialed-prerender
```

or the HTML `<meta>` element

```html
<meta http-equiv="Supports-Loading-Mode"
      content="uncredentialed-prerender">
```

As in the last example, based on its heuristics or informed by prerender triggers, the browser can attempt to prerender these linked-to news articles. Since they are cross-origin, however, the process is more restricted. The initial fetch, as well as any subresource fetches, are performed without credentials. If the response that comes back does not have the opt-in, then the result is discarded.

If the opt-in is present, then the resulting document is loaded into a cross-origin prerendering browsing context. Content there is restricted more heavily; not only are disruptive APIs prevented from working, but also storage access is initially not available. If the news site intends to personalize itself, e.g. to reflect subscriber status, then it would use code such as the following:

```js
function afterPrerendering() {
  // grab user data from cookies/IndexedDB
  // update the UI
  // maybe ask for camera access
}

if (!document.loadingMode || document.loadingMode.type === 'default') {
  afterPrerendering();
} else {
  document.addEventListener('loadingmodechange', () => {
    if (document.loadingMode.type === 'default') {
      afterPrerendering();
    }
  });
}
```

Alternately, if the page only cares about storage access (and not other facets of prerendering, such as ability to autoplay or trigger permission prompts), they could use a [proposed storage access API extension](https://github.com/privacycg/storage-access/issues/55):

```js
document.storageAccessAvailable.then(() => {
  // grab user data from cookies/IndexedDB
  // update the UI
});
```

### Cross-origin news aggregator with previews

The previous example potentially provides _instant_ loading, for news articles which opt in to being prerendered, and for cases where the browser decides to prerender. [Portals](https://github.com/WICG/portals/blob/master/README.md) allow the news aggregator to take things further, providing _seamless_ transitions between itself and the news content, at the cost of more manual handling of the prerendering work.

In particular, the news aggregator can create a `<portal>` element for each of its links to news articles, with its `src=""` attribute pointing to the news article URL. This portal can either be displayed directly to the user, to show them a scaled-down preview of the content, or it can be kept hidden initially. Then, when the user clicks the link, the news aggregator could provide a transition effect, by moving and scaling the portal appropriately before activating it:

```js
newsArticleLink.onclick = async e => {
  if (newsArticlePortal.state === 'closed') {
    // The content couldn't be portaled, likely because it didn't opt in.
    // Let the normal link click go through.
    return;
  }

  e.preventDefault();
  await animateToFullViewport(newsArticlePortal);
  newsArticlePortal.activate()
};
```
