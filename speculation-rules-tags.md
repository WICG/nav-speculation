# Speculation Rules Tags Explainer

This is an explainer for a proposed addition to the [speculation rules API](https://developer.mozilla.org/en-US/docs/Web/API/Speculation_Rules_API), which allows web developers to add "tags" to their speculation rules which are sent along with the speculative navigation request.

Speculation rules are an important component for speeding up the user's navigation across the web. This proposal allows them to be used without multiple parties stepping on each others' toes and accidentally failing to get this speedup.

## Use case

There may be multiple parties on a single referring page which are setting up speculation rules. These could include:

* The CDN serving the page
* The CMS or framework with which the site is built
* The developer responsible for the general template used for all pages on the site
* The developer responsible for the specific page

It can be useful for server code to respond differently to speculative navigation requests, depending on which source triggered them. For example, the more generic levels of the above hierarchy like CDNs or CMSes might want to conservatively reject speculative navigation requests that they don't know to be safe, using the more-limited information available to them like caching headers or site-wide configuration. But they don't want to reject requests where the site or page developer has pre-vetted the request as safe.

Today, there is no way for servers to perform this kind of differentiation. All speculative navigation requests appear the same to the server.

## The proposal

We propose asssociating each speculative navigation request with one or more "tags", which are string values. These tags are set in the speculation rules JSON syntax at either the individual rule level:

```json
{
  "prefetch": [
    "urls": ["next.html"],
    "tag": "my-prefetch-rules"
  ],
  "prerender": [
    "urls": ["next2.html"],
    "tag": "my-prerender-rules"
  ],
}
```

or at the overall level for all speculation rules in a ruleset:

```json
{
  "tag": "my-rules",
  "prefetch": [
    "urls": ["next.html"]
  ],
  "prerender": [
    "urls": ["next2.html"]
  ],
}
```

or both.

These tags are sent to the server with every speculative navigation request, via the new `Sec-Speculation-Tags` header. Examples:

```http
Sec-Speculation-Tags: null
Sec-Speculation-Tags: null, "cdn-prefetch"
Sec-Speculation-Tags: "my-prefetch-rules"
Sec-Speculation-Tags: "my-prefetch-rules", "my-rules", "cdn-prefetch"
```

(Here `null` is the default value, seen in action in the next section and discussed more [below](#the-default--no-tags-case).)

## Realistic example

Consider a CDN which wants to [conservatively](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/speculationrules#eagerness) prefetch all links on the page, but reject the prefetch links on the server side if they are not cached at the CDN edge. They might use speculation rules like the following, including a tag to identify them:

```json
{
  "tag": "awesome-cdn",
  "prefetch": [
    {
      "eagerness": "conservative",
      "where": { "href_matches": "/*", "relative_to": "document" }
    }
  ]
}
```

Then, consider the site owner who wants to add [moderately-eager](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/speculationrules#eagerness) prefetching for certain hero links. The site owner has vetted that these hero links are [safe to prefetch](https://developer.mozilla.org/en-US/docs/Web/API/Speculation_Rules_API#unsafe_speculative_loading_conditions), even if they're not edge-cached. The site owner does not bother including any tags:

```json
{
  "prefetch": [
    {
      "eagerness": "moderate",
      "where": { "selector_matches": ".hero-link" }
    }
  ]
}
```

Let's now consider several cases, starting from a user who has loaded a referrer page where both of these rulesets apply. In what follows, we'll assume Chromium's current heuristics for how eagerness values are interpreted, i.e. `"moderate"` means mouse hover on desktop/pointerdown on mobile, and `"conservative"` means pointerdown on all platforms.

### Hover over a hero link

Let's say the user hovers over a hero link to a non-edge-cached page. Then, because the user has hovered and not pointerdowned, only the site owner's rules trigger the speculative navigation request, so the browser sends the following header:

```http
Sec-Speculation-Tags: null
```

The CDN server code sees this incoming request. Since it does not contain the tag `"awesome-cdn"`, it lets the request pass through, instead of rejecting it because it's not edge-cached. Hooray!

### Pointerdown on a non-hero link

Let's say the user pointerdowns on a non-hero link. Then, the CDN's rules are the ones that trigger the speculative navigation request, so the browser sends the following header:

```http
Sec-Speculation-Tags: "awesome-cdn"
```

The CDN server code then processes this appropriately: if it is edge-cached, and thus known to be safe/cheap to prefetch, it serves the request, whereas if it's not, then it rejects the request. All is working as intended!

### Pointerdown, with no hover, on a hero link

The more interesting case is on mobile, where (at least in Chromium currently) there is no distinction between `"moderate"` and `"conservative"`: both rules will trigger on pointerdown, since hovering is not possible. There are other non-mobile cases that can trigger this, e.g. a user who navigates their desktop browser using only the keyboard and not the mouse.

In this case, if the user pointerdowns a hero link to a non-edge-cached page, the browser sees that both the page's and the CDN's rules apply. So, it sends the following header:

```http
Sec-Speculation-Tags: null, "awesome-cdn"
```

The CDN server code needs to take special care here: although `"awesome-cdn"` is present, _so is another tag_, so it needs to let the request pass through instead of rejecting it.

### Handling no `Sec-Speculation-Tags` header

When no `Sec-Speculation-Tags` header is included, but the `Sec-Purpose: prefetch` header is included (or `Sec-Purpose: prefetch;prerender` for prerenders) then the CDN server code could still reject when not edge-cached under the assumption that the request was possibly made by an older browser which does not support Speculation Rules Tags. Note, such requests may also be a non-Speculation Rules prefetch—as described in the next section—but until the Speculation Tags support becomes widely supported it may be safer to reject such speculations under the assumption that they might be from the CDN's speculation rules.

## Additional benefits

Today, speculative navigation requests are mostly indistinguishable from speculative subresource requests. For similar reasons to our original use case, it can be useful for different parts of the server stack to distinguish between these. By adding a tag header that is sent along with speculative navigation requests, they can now distinguish. See [#337](https://github.com/WICG/nav-speculation/issues/337) for a request from a CDN for this ability.

(In Chromium, there are very minor differences, e.g. the inclusion of `Upgrade-Insecure-Requests: 1`. It's not clear whether these are per spec, and an explicit signal would be much better.)

Today, if a page contains multiple speculation rules, it can be hard to differentiate them in DevTools. Top-level tags could be surfaced in DevTools to improve this experience. See [#298](https://github.com/WICG/nav-speculation/issues/298) for a web developer request of this sort. (See also the [`DedicatedWorkerGlobalScope` `name` property](https://developer.mozilla.org/en-US/docs/Web/API/Worker/Worker#name), which is a precedent of adding such information _only_ for debugging.)

## Design considerations and alternatives considered

### Header design and naming

The `Sec-Speculation-Tags` header is a [structured field](https://www.rfc-editor.org/rfc/rfc8941) which contains a list of strings or tokens.

We've chosen the name "speculation tags" instead of "speculation rules tags" to be future-proof against new ways of triggering speculative navigation requests, e.g. the (now-closed) [proposal to extend `<link>`](https://github.com/WICG/nav-speculation/issues/307).

We've proposed using the `Sec-` prefix since we do not believe there are use cases for allowing web developers to manipulate these headers from JavaScript via a service worker, or set them with `fetch()` calls. Allowing such manipulation would not necessarily break anything, but it is probably simpler for web developers if they can always trust that a `Sec-Speculation-Tags` header comes from an actual speculation rules-initiated request.

It would be nice if we could merge the tags into the existing `Sec-Purpose: prefetch` and `Sec-Purpose: prefetch;prerender` headers that are sent with speculative navigation requests. However, the structured headers specification doesn't seem to allow anything here that would work. In particular, you cannot attach inner lists as parameters, so e.g. `Sec-Purpose: prefetch;tags=("my-tag")` is not possible.

### The cross-site case

We currently propose that this header is only sent for same-site speculative navigation requests, for privacy reasons.

Allowing additional information to be sent with a speculative navigation request across sites provides a cross-site communications channel. This isn't really more powerful than the communications channel that already exists via speculative navigation request URLs. The specified [protections](./fetch.md), e.g. not performing prefetches if the destination has cookies, would prevent this information from being joined to a cross-site user identity.

However, we don't have compelling use cases for extending this across sites, so it seems simpler and safer to just constrain it. We can always explore expanding this in the future if a use case arises.

### The default / no tags case

There are two possible models for what happens when no tags apply to a speculative navigation request:

* Treat this as having no tags. In that case, no header is sent, [per guidance in the structured fields specification](https://www.rfc-editor.org/rfc/rfc8941#section-3.1-6).

* Treat this as having a sort of default tag. We've chosen to represent this with the token `null`, so that the header `Sec-Speculation-Tags: null` is sent.

The latter works better for our use case, for two reasons. First, it helps with the bonus use case mentioned [above](#additional-benefits) of distinguishing speculative navigation requests from speculative subresource requests, even if none of the speculation rules authors have bothered to add a tag. Second, it gives more information in cases like our [realistic example](#pointerdown-with-no-hover-on-a-hero-link), where multiple rules apply to a speculative navigation request but not everyone has added a tag.

Using `null` for the default tag is somewhat arbitrary. Other choices are possible, e.g. a token like `default`, or even a string like `"default"` or `""` if we are willing to deal with the possibility of collision with developer-supplied tags.

### Location of the tags within the JSON

We allow the tags to be supplied both at the top level, and on a per-rule level. We suspect the former will be most commonly useful, for use cases like the one we opened with. In such cases, it would be annoying to make authors repeat the same tag in every rule. But the latter could sometimes be useful for specific situations, and it would be unhelpful to force authors to split their speculation rules into two for such cases.

Due to how the specification is currently written, the choice of where to put rules has different implications for how older browsers process the rules. Top-level keys besides `"prefetch"` and `"prerender"` are ignored by browsers implementing the previous specification, and so adding the tag there becomes a simple progressive enhancement. However, unknown fields in individual rules cause the entire rule to be thrown out in older browsers, which might or might not be desired.

This divergence isn't really intentional, and we're contemplating making individual rule parsing laxer to avoid this kind of situation in the future. (See [issue #244](https://github.com/WICG/nav-speculation/issues/244).) In the meantime, developers will need to take care during the transition period.

### Multiple applicable rules

It's possible that multiple tags apply to a single speculative navigation request. A [realistic example](#pointerdown-with-no-hover-on-a-hero-link) is given above. It can also arise simply from duplicative rules, or from tags added at both the ruleset level and at the individual rule level.

To present these tags in the header, they are all collected, deduplicated, and then sorted lexicographically, with the default `null` tag first before any string tags.

The process for determining exactly which rules could trigger a given speculative navigation request, and thus which tags should be included, is slightly tricky. The realistic example shows one case where multiple rules can apply, but other cases are worse. For example, consider a case like

```json
{
  "prefetch": [
    {
      "tag": "tag1",
      "where": { "selector_matches": "*" },
      "eagerness": "moderate"
    },
    {
      "tag": "tag2",
      "urls": ["next.html"],
      "eagerness": "immediate"
    },
    {
      "tag": "tag3",
      "urls": ["next.html"],
      "referrer_policy": "no-referrer",
      "eagerness": "immediate"
    }
  ]
}
```

If the user hovers over and then clicks on `<a href="next.html">click me</a>`, which of these rules apply? Should it only be the `"tag2"` rule, because it ran first (immediately, on page load)? But `"tag1"` intuitively seems like it should apply, as it's targeting the user hovering over any link. What about the `"tag3"` rule, which requests a speculative navigation request with no referrer policy, but will never actually get executed because the prefetch record cache already contains an entry for `next.html`?

The answer we give is that all three tags must be included. Intuitively, this makes sense, since if we removed any two of them, the remaining one would still have triggered a relevant prefetch. The way this intuition is concretely specified is that we include the tags for any rule which:

* would cause the same URL to be fetched; and
* has the an eagerness equal to or more eager than than the eagerness of the rule that actually triggered the prefetch.

(Note: the first criteria is a bit complicated due to the interaction with `No-Vary-Search`. See [the spec](https://wicg.github.io/nav-speculation/speculation-rules.html#collect-tags-for-matching-speculative-load-candidates) for full details.)

(Side note: before figuring out which rules _could apply_, there's the question of which rule _will actually trigger the speculative load_. In the above example, the question is whether the `"tag2"` rule will trigger, including the normal referrer, or whether the `"tag3"` rule will trigger, including no referrer. The specification processes rules in the order they are encountered, and ignores redundant ones, so in this case the `"tag2"` rule will trigger and the `"tag3"` rule will be ignored.)

## Accessibility, privacy, and security considerations

This feature has no accessibility considerations.

This feature could have minor privacy considerations, on top of the existing ones for speculative loads in general, if it were allowed to be used across sites. However, [we plan to disallow that for now](#the-cross-site-case).

This feature does not have any security considerations, on top of the existing ones for speculative loads in general.

### W3C TAG Security and Privacy Questionnaire answers

> 01.  What information does this feature expose, and for what purposes?

The string tags provided by the website in its speculation rules markup are exposed back to the same site via the `Sec-Speculation-Rules` header, to allow the website to tell which set of speculation rules triggered a speculative load.

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

The larger speculation rules specification, of which this is a part, has [Security considerations](https://wicg.github.io/nav-speculation/speculation-rules.html#security-considerations) and [Privacy considerations](https://wicg.github.io/nav-speculation/speculation-rules.html#privacy-considerations) sections.

> 17.  Do features in your specification enable origins to downgrade default security protections?

No.

> 18.  What happens when a document that uses your feature is kept alive in BFCache (instead of getting destroyed) after navigation, and potentially gets reused on future navigations back to the document?

This particular sub-feature does not interact with bfcache. Speculation rules in general works after being restored from bfcache, including sending the tags that this sub-feature enables.

> 19.  What happens when a document that uses your feature gets disconnected?

Speculative loading does not work in disconnected documents.

> 20.  Does your spec define when and how new kinds of errors should be raised?

If tag parsing fails, the speculation rules fail to parse, which has the same failure mode as before. (A console warning.)

> 21.  Does your feature allow sites to learn about the user's use of assistive technology?

No.

> 22.  What should this questionnaire have asked?

Seems fine.

## Stakeholder feedback

* Support from Cloudflare and Speed Kit platforms in [#336](https://github.com/WICG/nav-speculation/issues/336) and [#337](https://github.com/WICG/nav-speculation/issues/337)
* [Gecko standards-positions request](https://github.com/mozilla/standards-positions/issues/1172)
* [WebKit standards-positions request](https://github.com/WebKit/standards-positions/issues/54#issuecomment-2635730709)
