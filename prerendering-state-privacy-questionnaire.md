# Privacy Questionnaire For `document.prerendering`

#### 2.1 What information might this feature expose to Web sites or other parties, and for what purposes is that exposure necessary?

This feature exposes to a page that it is being loaded and run in a prerendering context, that is, it is not yet interactive and hasn't been intentionally navigated to by the user.

It also exposes the time at which the page is transfered into the active/interactive browsing context, that is, when the user intentionally navigated to it.

#### 2.2 Is this specification exposing the minimum amount of information necessary to power the feature?

I believe so: it's just a single bit (which is needed by page authors) and an event to inform them of changes to it.

#### 2.3 How does this specification deal with personal information or personally-identifiable information or information derived thereof?

The value of `document.prerendering` can't, as far as I can tell, be used to transfer information other than whether the document is currently in a prerendering context or not.

#### 2.4 How does this specification deal with sensitive information?

N/A see above.

#### 2.5 Does this specification introduce new state for an origin that persists across browsing sessions?

No

#### 2.6 What information from the underlying platform, e.g. configuration data, is exposed by this specification to an origin?

None

#### 2.7 Does this specification allow an origin access to sensors on a user’s device

No

#### 2.8 What data does this specification expose to an origin? Please also document what data is identical to data exposed by other features, in the same or different contexts.

Whether or not the document is being prerendered. Also, the time at which a user navigates, which would be visible in a normal navigation as well.

#### 2.9 Does this specification enable new script execution/loading mechanisms?

No

#### 2.10 Does this specification allow an origin to access other devices?

No

#### 2.11 Does this specification allow an origin some measure of control over a user agent’s native UI?

No - this API is read-only

#### 2.12 What temporary identifiers might this this specification create or expose to the web?

None.

#### 2.13 How does this specification distinguish between behavior in first-party and third-party contexts?

It does not, the functionality is unchanged in both cases:

* A cross-origin iframe vs a same origin-iframe inside a prerendering page
* A cross-origin prerendering page vs a same-origin prerendering page (as compared to origin of the current interactive page).

#### 2.14 How does this specification work in the context of a user agent’s Private Browsing or "incognito" mode?

Unchanged from regular mode

#### 2.15 Does this specification have a "Security Considerations" and "Privacy Considerations" section?

This specification is part of the larger revamped prerendering effort, which will have dedicated security and privacy sections dealing with the larger questions raised there. Currently those discussions are in the explainer, but they will move into the specification as the larger effort continues to get more rigorous.

This particular part of the prerendering effort will likely not be mentioned in the eventual security and privacy sections, as none of the larger feature's security and privacy concerns manifest in the exposure of this API.

#### 2.16 Does this specification allow downgrading default security characteristics?

N/A

#### 2.17 What should this questionnaire have asked?

N/A
