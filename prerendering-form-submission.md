# Speculation Rules form submission Explainer

Currently, form submissions cannot activate prerendered pages by design. This is an explainer for a proposed addition to the [Speculation Rules API](https://developer.mozilla.org/en-US/docs/Web/API/Speculation_Rules_API), which allows web developers to specify `form_submission` in their speculation rules to specify that a prerendered page can only be activated by a form submission.
Examples include a simple search form which results in a “/search?q=XXX” GET request navigation, [support of which has been requested by web developers](https://issues.chromium.org/issues/346555939).


## The proposal

Introduce the `form_submission` field to speculation rules, allowing web developers to specify which speculative navigation is a form submission one. This will only be available for GET form-based speculations.

It should be noted the speculation will need to be triggered by the page in some manner (e.g. by injecting the rule with JavaScript on hovering over the submit button). This proposal does not add functionality to trigger the speculation, but simply allows a previously-initiated speculation to be matched upon navigation.

### More details

Note that this field is only required for prerender. On the other hand, prefetch speculation rules can be used by form navigations without specifying this field.
The key difference is that unlike prefetch, which only downloads HTML, prerendering actually starts the navigation. Because parameters are involved, using a standard (non-form) prerender for a form submission will result in breakage."

## Example

This example creates 2 prerendered pages, one being a form submission, and the other being a non-form submission.

Any of the them can be activated by an activation navigation which matches corresponding parameters.

```json
{
  "prerender": [
    {
      "form_submission": true,
      "urls": ["/expect_form_submission.html"]
    }
  ],
  "prerender": [
    {
      "urls": ["/not_expect_form_submission.html"]
    }
  ]
}
```

## Design considerations and alternatives considered

Modify the existing logic to allow prerender activation by form submission without this field.

The navigation history entries that are created by prerender have an an initial navigation are not form submissions. Form submissions are subject to extra checks in Chrome at least that would not be checked on initial prerender. Allowing speculation rules to specify the form submission field enables prerender to create the initial prerender in as a form submission navigation. This allows additional checks to complete and avoids wasting resources on prerendering a page which is not eligible, such as CSP disallowing `form-action`.

For these reasons, this idea is abandoned.

## Accessibility, privacy, and security considerations

This feature has no accessibility considerations.
This feature does not have any privacy considerations or security considerations, on top of the existing ones for speculative loads in general.

### W3C TAG Security and Privacy Questionnaire answers

> 01.  What information does this feature expose, and for what purposes?

None.

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

This isn't applicable, as prerendered pages cannot be kept in BFCache.

> 19.  What happens when a document that uses your feature gets disconnected?

Speculative loading does not work in disconnected documents.

> 20.  Does your spec define when and how new kinds of errors should be raised?

If the field parsing fails, the speculation rules fail to parse, which has the same failure mode as before. (A console warning.)

> 21.  Does your feature allow sites to learn about the user's use of assistive technology?

No.

> 22.  What should this questionnaire have asked?

Seems fine.

## Stakeholder feedback

- [Requested by web developers](https://g-issues.chromium.org/issues/346555939)
- [Workarounds implemented by WordPress](https://github.com/WICG/nav-speculation/issues/322#issuecomment-2162167369)

