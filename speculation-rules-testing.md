# Web Platform Tests Plan (Speculation Rules)

Web platform tests for speculation rules need to test:

1. **candidate gathering**, i.e., that the URLs and associated data are properly gathered from the document
1. **execution**, i.e., that executing a prefetch or other action has the expected result on network activity, script execution, storage, etc., and the results are usable on navigation

The intermediate piece, **policy**, is largely left to UA discretion and so can be largely managed by vendor-specific tests. If the specification does specify that an action *must* or *must not* be taken, that can be tested as well.

In order to control for policy differences, it is necessary to provide internal hooks to allow tests to override policy.

## Test Library

Tests will have a JavaScript library that provides high-level features to hold the execution of speculative actions, describe the gathered candidates, and deterministically execute them. This library will expose a simple promise-based interface, roughly along these lines (TypeScript syntax):

```ts
interface SpeculationCandidate {
    url: URL;
    action: 'prefetch'|'prefetchWithSubresources'|'prerender';
    requires: ('anonymous-client-ip-when-cross-origin')[];
}

interface TestDriverSpeculation {
    // Assume control of speculation.
    setup_for_test(): Promise<void>;

    // Returns the first valid candidate found to match the predicate.
    first_candidate_matching(predicate: (c: SpeculationCandidate) => boolean): Promise<SpeculationCandidate>;

    // Executes the given candidate.
    execute(c: SpeculationCandidate): Promise<void>;
}
```

## Vendor (Chromium)

The Chromium `content_shell` will expose a test-only Mojo interface which provides the necessary hooks to support these operations, and the test library will be implemented in terms of these hooks. Other vendors could implement vendor-specific equivalents.

## WebDriver

In the longer term, these hooks should be formalized as an extension of [test_driver](https://web-platform-tests.org/writing-tests/testdriver-extension-tutorial.html), the `testdriver-vendor.js` of which would continue to use the aforementioned vendor hooks.

In order to support `wpt.live` and other environments which use WebDriver, a WebDriver-based version of these hooks would be implemented in `testdriver-extra.js` and plumbed through the WebDriver executor and vendor implementations. For Chrome, this would require implementing it in Chromedriver and the Chrome DevTools Protocol.

## TBD: Client IP Anonymization

It's not obvious how to test client IP anonymization (for `"requires": ["anonymous-client-ip-when-cross-origin"]` rules) in the WPT environment, which runs locally to a single host. More work is needed to determine the best way to reflect this. For example, a request header could be sent in lieu of routing through a proxy, to indicate that in non-test mode the IP would have been anonymized. However, it would be preferable to use some strategy which is closer to the non-test behavior.