# Chrome 2023 Experiment Overview

In early 2023, Google Chrome will be running an origin trial to allow developers to try out several new enhancements related to speculation rules and prefetching. These enhancements are focused around allowing the browser to automatically assist with prefetching with minimal developer work, and allowing developers to measure when their pages are successfully prefetched.

## Opting into the origin trial

Developers can sign up for an [origin trial](https://developer.chrome.com/docs/web-platform/origin-trials/) token.

> **Note**
> This trial is not yet available. We'll update this with a link when it launches.

Most developers will only need a token for their own origin, and can use it the usual way.

```http
Origin-Trial: [token issued to your origin]
```

```html
<meta http-equiv="origin-trial" content="[token issued to your origin]">
```

For this trial, Chrome will also accept a third-party token issued to another origin, as long as either:

* an external script loaded from that origin adds it, or
* the server delivers the document response with a `Speculation-Rules` HTTP response header which loads speculation rules and an `Origin-Trial` HTTP response header issued to that origin

```http
Origin-Trial: [third-party token for https://rules-provider.example]
Speculation-Rules: "https://rules-provider.example/speculationrules.json"
```

## HTTP-fetched speculation rules

Some developers prefer to deliver speculation rules out of line. You can do this using the `Speculation-Rules` response header.

```http
Speculation-Rules: "/speculationrules.json"
```

This will be fetched and cached like any other subresource, though at a lower priority since it doesn't block the current page load. This resource must use the correct MIME type and, if it is cross-origin, pass a [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) check.

```http
Content-Type: application/speculationrules+json
Access-Control-Allow-Origin: *
```

## Automatic link finding

With this enhancement, the browser can automatically react find links in your page which the user is likely to click. The developer simply needs to communicate which links are appropriate to prefetch, since some servers might exhibit side effects for `GET` requests.

You can do this by using [URL patterns](https://developer.mozilla.org/en-US/docs/Web/API/URL_Pattern_API) and simple boolean expressions using "and", "or", and "not". Support for selecting links using CSS selectors is planned. (Let us know if this would make a difference to you!)

```json
{"prefetch": [
   {"source": "document",
    "where": {"or": [
       {"href_matches": "/articles/*\\?*",
        "relative_to": "document",
        "referrer_policy": "strict-origin-when-cross-origin"},
       {"href_matches": "/products/*\\?*",
        "relative_to": "document",
        "referrer_policy": "strict-origin-when-cross-origin"}
    ]}}
]}
```

## When automatic prefetching occurs

In Chrome 110, this experiment will cause Chrome to prefetch up to some small number (currently 5) of URLs when the pointer is down (i.e., mouse down or touch start), which typically occurs between 100 and 200 milliseconds before click, if your speculation rules permit it.

As the experiment continues, we may modify this heuristic or add new ones, for example based on hover dwell time.

## Observing and measuring prefetch

**In the lab**: Prefetches are visible in the Network panel of Chrome DevTools. An in-development Preloading panel will expose more insight. Potential issues are logged to the Console panel.

**On the server**: prefetch requests are marked with a request header.

```http
Sec-Purpose: prefetch
```

**On the client**: Documents which were prefetched can observe this in the [performance timeline](https://developer.mozilla.org/en-US/docs/Web/API/Performance_Timeline).

```javascript
performance.getEntriesByType('navigation')[0].deliveryType === 'navigational-prefetch'
```

Fields of the performance timing entry which occurred before navigation start are [clamped](https://github.com/w3c/resource-timing/issues/360). That is, they will be non-negative, and timestamps will still appear to occur in the usual order, if perhaps particularly fast because they complete "instantaneously".

## Caveats

There are a few potential pitfalls to be aware of:

* URL patterns which don't specify the query string only match links with no query string. Adding `?*` (with the required escaping for URL pattern and JSON syntax) or using `search: '*'` for the long form syntax will allow you to match links with any query parameters.
* If you use a restrictive [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP), you may need to adjust your CSP. For inline speculation rules, you'll need to permit inline scripts generally, use nonces or hashes, or use the experimental `'inline-speculation-rules'` source. For HTTP-fetched rules, the origin your rules is fetched from will need to be included in the allow list.
* If you specify a non-default [referrer policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy), it will be respected. If it is not [sufficiently strict](https://wicg.github.io/nav-speculation/prefetch.html#list-of-sufficiently-strict-speculative-navigation-referrer-policies), then the prefetch will not occur. You can override the referrer policy which applies to your prefetches using `"referrer_policy"` in your speculation rules, or using the `referrerpolicy` attribute on individual links.
* If you use HTTP-fetched speculation rules, and especially if fetched cross-origin, note that URLs and URL patterns in your speculation rules are resolved relative to the URL of your speculation rules (after redirects). If you want to specify URLs relative to the document instead, you can specify `"relative_to": "document"` to adjust this behavior. This may be particularly useful if you wish to select some or all same-origin links.
* If you use HTTP-fetched speculation rules with a cross-origin URL, make sure the server sends a suitable `Access-Control-Allow-Origin` header to permit this.
* If you select cross-origin links, note that for privacy reasons they cannot be prefetched with existing cookies and credentials. For this reason, such links will not be prefetched if credentials are found.
* Chrome does not yet follow redirects during prefetching.