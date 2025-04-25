# Clear-Site-Data integration with Prerender and Prefetch

## Summary

We propose adding two new values to the [`Clear-Site-Data`](https://w3c.github.io/webappsec-clear-site-data/#header) header to help developers target clearing the prerender and prefetch cache: `"prefetchCache"` and `"prerenderCache"`.

**GitHub issue**: [Specify clear-site-data integration, and special keywords for prefetch and prerender · Issue #357 · WICG/nav-speculation](https://github.com/WICG/nav-speculation/issues/357)

## Background

The `Clear-Site-Data` header is a powerful tool for web developers to clear various types of data stored by a website, such as cookies and storage. Currently, the `"cache"` value of this header includes the functionality to evict prefetches and cancel prerenders. However, there is a need for more granular control to allow developers to specifically target these actions without affecting other cached data.

One specific [issue](https://github.com/WICG/nav-speculation/issues/352) brought up by Shopify related to prerendering is that when a user adds a product to the cart and then navigates to a prerendered page, the cart content or cart count displayed on the prerendered page does not reflect the recent addition to the cart. This discrepancy occurs because the prerendered page shows the state before the product was added to the cart.

While there could be workarounds like using local storage flags and forcing page reloads, these are more complicated and would go against maintaining the purpose and efficiency of prerendering. Using the `Clear-Site-Data` header value `"prerenderCache"` to specifically target clearing the prerender cache would help Shopify ensure pages are in sync.

## Implementation

On top of the existing values for the `Clear-Site-Data` header, we propose also including:

- `"prefetchCache"`: Used to evict prefetches that are scoped to the referrer origin.
- `"prerenderCache"`: Used to cancel prerenders that are scoped to the referrer origin.

These added values will not affect other caches, just their respective targets.

## Example code

**Client Side:**

```js
addToCartButton.onclick = () => {
  fetch("/add-to-cart", {
    method: "POST",
    body: JSON.stringify(cartData),
    headers: {
      "Content-Type": "application/json"
    }
  })
  .then(response => {
    if (response.ok) {
      console.log("Item added to cart successfully.");
    } else {
      console.error("Failed to add item to cart.");
    }
  });
};
```

**Server Side:**

```js
const express = require('express');
const app = express();
app.use(express.json());

app.post('/add-to-cart', (req, res) => {
  const cartData = req.body;
  addItemToCart(cartData);

  // Clear prefetch and prerender caches
  res.set('Clear-Site-Data', '"prefetchCache", "prerenderCache"');
  res.status(200).send('Item added to cart and caches cleared.');
});

function addItemToCart(cartData) {
  console.log('Item added to cart:', cartData);
}
```

## Clear-Site-Data response header implementation

| Header                            | Prefetch cache cleared | Prerender cache cleared |
|----------------------------------|-------------------------|--------------------------|
| `Clear-Site-Data: "cache"`       | ✅                      | ✅                       |
| `Clear-Site-Data: "prefetchCache"` | ✅                      |                          |
| `Clear-Site-Data: "prerenderCache"`|                         | ✅                       |

## Choice of origin scope

There have been [discussions](https://github.com/w3c/webappsec-clear-site-data/issues/87) around how to scope different types of data in the context of the `Clear-Site-Data` header. For `prefetchCache` and `prerenderCache`, we’ve decided to scope these to the **origin**.

This decision aligns with the approach taken for DOM-accessible storage (e.g., `localStorage`, `IndexedDB`) and execution contexts (e.g., service workers), both of which are scoped by origin. This approach simplifies mental models for developers and keeps consistency across the web platform.

Additionally, prefetching and prerendering are security-sensitive operations. Scoping by origin ensures a clear boundary and avoids cross-origin leakage.

## Same-Origin and Cross-Origin Prefetch and Prerender Handling

When the server sends a `Clear-Site-Data` header with `prefetchCache` and/or `prerenderCache`, prefetches and prerenders that are same-origin will be cleared. Currently, prerendering is restricted to same-origin documents by default.

However, support exists for cross-origin prefetch and credentialed-prerender. In such cases, prefetches and prerenders with the **same referrer origin** as the response’s origin will also be cleared.

For example:
- If Origin A sends `Clear-Site-Data: "prefetchCache"`, all prefetches with referrer origin A will be cleared, even if the prefetched resource is from a different origin.
- Prefetches where the response’s origin is A but the referrer origin is not A will **not** be cleared.

## Which value(s) to pass in the header?

The current implementation decouples `prefetchCache` and `prerenderCache`:
- Passing only `prefetchCache` clears **only** the prefetch cache.
- Passing only `prerenderCache` clears **only** the prerender cache.

In most cases, clearing prefetch implies the associated prerender is out-of-date and should be cleared. However, if a prerendered page is kept in sync via mechanisms like `BroadcastChannel`, separating the two is useful.

**TL;DR**:
- If you're **not** using something like `BroadcastChannel`, and want to ensure consistency, pass **both** `prefetchCache` and `prerenderCache`.
- Otherwise, use the one relevant to your use case.

## Accessibility, privacy, and security considerations

This feature has no accessibility considerations.

This feature has no privacy considerations.

This feature does not have any security considerations, on top of the existing ones for speculative loads in general.

### W3C TAG Security and Privacy Questionnaire answers

> 01.  What information does this feature expose, and for what purposes?

The purpose of these values is not to reveal information, but to give server-side applications fine-grained control over the clearing of specific speculative caches.

> 02.  Do features in your specification expose the minimum amount of information necessary to implement the intended functionality?

Yes.

> 03.  Do the features in your specification expose personal information, personally-identifiable information (PII), or information derived from either?

No.

> 04.  How do the features in your specification deal with sensitive information?

No sensitive information is dealt with.

> 05.  Does data exposed by your specification carry related but distinct information that may not be obvious to users?

No.

> 06.  Do the features in your specification introduce state that persists across browsing sessions?

No.

> 07.  Do the features in your specification expose information about the underlying platform to origins?

No.

> 08.  Does this specification allow an origin to send data to the underlying platform?

No.

> 09.  Do features in this specification enable access to device sensors?

No.

> 10.  Do features in this specification enable new script execution/loading mechanisms?

No.

> 11.  Do features in this specification allow an origin to access other devices?

No.

> 12.  Do features in this specification allow an origin some measure of control over a user agent's native UI?

No.

> 13.  What temporary identifiers do the features in this specification create or expose to the web?

None.

> 14.  How does this specification distinguish between behavior in first-party and third-party contexts?

It does not distinguish.

> 15.  How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

The same as in normal modes.

> 16.  Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

No.

> 17.  Do features in your specification enable origins to downgrade default security protections?

No.

> 18.  What happens when a document that uses your feature is kept alive in BFCache (instead of getting destroyed) after navigation, and potentially gets reused on future navigations back to the document?

This particular sub-feature does not interact with bfcache.

> 19.  What happens when a document that uses your feature gets disconnected?

The behavior of these new directives is unaffected by that disconnection directly.

> 20.  Does your spec define when and how new kinds of errors should be raised?

No, the proposed feature does not define any new kinds of errors to be raised. 

> 21.  Does your feature allow sites to learn about the user's use of assistive technology?

No.

> 22.  What should this questionnaire have asked?

Seems fine.