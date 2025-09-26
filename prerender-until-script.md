# Explainer: The `prerender_until_script` Speculation Rule

## Introduction

This document proposes a new action for the Speculation Rules API, `prerender_until_script`. This action is designed to provide developers with an intermediate option between the existing `prefetch` and `prerender` actions.

The Speculation Rules API currently offers two main actions: `prefetch`, which only fetches the main document, and `prerender`, which fetches and fully renders the page, including executing all scripts. While both are powerful, developers have expressed a desire for a middle ground that provides more performance benefits than `prefetch` without the full resource commitment and immediate script execution of `prerender`.

For some pages, executing JavaScript during the prerendering phase can be unnecessary or premature. For example, scripts for analytics, ads, or third-party widgets might be better deferred until the user has actively navigated to the page.

The `prerender_until_script` action fills this gap. It provides the network and parsing benefits of prerendering—fetching the main document and allowing the browser's preload scanner to discover and download critical subresources, while deferring all script execution until activation. This gives developers a new level of control to fine-tune their performance strategies.

## Goals

*   Introduce an intermediate speculation action between `prefetch` and `prerender`.
*   Provide a mechanism to prerender a page without executing any JavaScript until the page is activated.
*   Allow developers to gain the performance benefits of fetching and parsing a page and its subresources, without the cost of early script execution.
*   Give developers more granular control over the performance-versus-resource-usage tradeoff.
*   Enable a "progressive speculation" strategy, where a `prerender_until_script` can be used with an `eager` or `moderate` eagerness, and a full `prerender` can be used with a `conservative` eagerness.
*   Maintain the security and privacy benefits of the existing prerendering framework.

## Key Scenarios / Use Cases

*   **Content sites with heavy interactive elements:** A news article or blog post could be prerendered to display the text content instantly, while the JavaScript for comments sections, social media widgets, and other interactive elements is deferred until the user activates the page.
*   **E-commerce product pages:** A product page could be prerendered to show the main product image and description, while scripts for engagement calculation and conversion tracking are paused until the user navigates to the page.

## Proposed Solution

We propose a new action, `prerender_until_script`, which can be used within a `<script type="speculationrules">` element. When the browser processes a speculation rule with this action, it will initiate a prerender that:

1.  Fetches the document.
2.  Parses the HTML and constructs the DOM. The user agent's preload scanner can discover and begin downloading subresources (e.g., stylesheets, images) referenced in the document.
3.  Renders the page. If a parser-blocking `<script>` element is encountered, rendering will be paused at that point until activation.
4.  Pauses all script execution. This includes `<script>` blocks, timers, and promise resolutions.
5.  When the user navigates to the prerendered page, the page is activated, and all paused scripts are executed in order.

### Example

```html
<!-- initiator.html -->
<script type="speculationrules">
{
  "prerender_until_script": [
    {
      "source": "list",
      "urls": ["/heavy-script-page.html"]
    }
  ]
}
</script>

<a href="/heavy-script-page.html">Link to a page with heavy scripts</a>
```

```html
<!-- heavy-script-page.html -->
<script defer src="deferred-script.js" id="deferred-script"></script>
<script async src="async-script.js" id="async-script"></script>
<img src="image1.jpg" id="first-image"/>
<script id="first-blocking">
{
  // Heavy script... 
}
</script>
<img src="image2.jpg"/>

```

In this example, `/heavy-script-page.html` will be prerendered, but its scripts will not run until the user clicks the link and the page is activated.

### Workflow Breakdown

Here is a step-by-step breakdown of how a user agent would process the `heavy-script-page.html` example:

**Phase 1: Prerendering (Pre-Activation)**

1.  The user agent begins parsing the document.
2.  The `deferred-script` script is found. The browser starts fetching `deferred-script.js` and queues it for execution after the document has finished parsing and activation.
3.  The `async-script` script is found. The browser starts fetching `async-script.js`. Once downloaded, it is ready to be executed immediately after the page is activated.
4.  The `first-image` element is found, and the browser starts fetching `image1.jpg`.
5.  The parser encounters the `first-blocking` script. At this point, because the `scripting mode` is `paused-until-activation`, the parser is paused.
6.  While waiting for activation, the user agent may optionally prefetch `image2.jpg`.
7.  During this entire phase, **no script elements are executed**.

**Phase 2: Activation**

8.  The user clicks the link, and the prerendered document is activated.

**Phase 3: Script Execution (Post-Activation)**

9.  The parser resumes. The `first-blocking` script is the first to be executed.
10. After `first-blocking` finishes, the parser continues from where it left off, processing the rest of the document.
11. The `async-script` script (if it has finished downloading) is executed. `async` scripts execute as soon as they are ready post-activation, independently of the document parsing order.
12. Once the document has finished parsing, the `deferred-script` script (if it has finished downloading) is executed. `defer` scripts always execute after the document is fully parsed, in the order they appeared in the HTML.
 
## Detailed Design Discussion

The `prerender_until_script` action is implemented as an extension to the existing prerendering specification. The key technical changes are:

*   A new `prerender_until_script rules` list is added to the `speculation rule set` struct.
*   A `should pause scripts` boolean is added to the `prerender candidate` struct to track whether scripts should be paused.
*   A `scripting mode` is added to the `navigable` struct, with a state of `paused-until-activation`.

A key design consideration for this feature is defining the precise scope of what "pausing script execution" entails. The ideal goal is to prevent any developer-authored scripts from running until activation. To achieve this, we need to consider all possible **scripting entry points**. If all entry points are successfully blocked, then no script can run, and therefore no subsequent tasks like timers (`setTimeout`) or promise resolutions can be queued by that script.

The most direct entry point is the `<script>` element. The current specification focuses on this, deferring the execution of all scripts of this type—whether parser-blocking, `async`, or `defer`, until the page is activated.

To provide a complete solution, other entry points must be considered. These include `javascript:` URLs and inline event handlers (e.g., `onload`). Deferring these handlers seems like the most predictable behavior for developers, but this requires careful specification. **We are actively seeking feedback from the community on how these non-`<script>` entry points should be handled.**

Also, it is a long-standing web development best practice to separate HTML structure from JavaScript behavior by avoiding inline event handlers (e.g., `<div onclick="...">`) in favor of registering event listeners from within `<script>` elements (e.g., `div.addEventListener('click', ...)`). This feature reinforces that best practice. Pages that follow this principle will have their behavior reliably deferred by `prerender_until_script`, as all of their scripting logic will be contained within `<script>` elements.

The current specification focuses on the essential mechanism of deferring `<script>` element execution. The more nuanced behaviors for other entry points are a topic for further discussion and will be detailed in future revisions of the spec.

Upon activation, the `finalize activation` algorithm sets the `scripting mode` to `enabled` and resumes script execution, processing the queue of scripts in the appropriate order.

## Developer Impact

For developers, this is a powerful new tool for performance optimization. Pages that were previously poor candidates for prerendering due to their reliance on JavaScript can now benefit from this feature.

## Security and Privacy Considerations

The `prerender_until_script` action inherits all the security and privacy protections of the standard prerendering mechanism. All restrictions, such as those on cross-site navigations and access to user-facing APIs, remain in effect.

This feature does not introduce any new security or privacy concerns beyond those already addressed by the prerendering specification. By deferring script execution until activation, it offers a model with a more limited execution context during the speculation phase, which can be a desirable characteristic for some applications.

## Considered Alternatives

### No Prerendering

The simplest alternative is to not prerender pages with heavy scripts. However, this means that users navigating to these pages will not experience the performance benefits of prerendering. `prerender_until_script` provides a better option by allowing the most time-consuming parts of the page load (network and parsing) to be done in advance.

### Modifying Pages to be Prerender-Friendly

Another alternative is for developers to modify their pages to be more "prerender-friendly," for example, by delaying script execution manually using the `prerenderingchange` event. While this is a valid approach, `prerender_until_script` provides a simpler, declarative way to achieve a similar result without requiring significant code changes. It also provides a stronger guarantee that *no* scripts will be executed, which can be difficult to achieve manually.

### Alternative Naming

The initial proposal for this feature used the name `preparse`. Other names, such as `prescan` and `prefetch_with_subresources`, were also considered. The name `prerender_until_script` was chosen to make it clear that this is a form of prerendering, but with a specific modification to the script execution lifecycle. This naming helps to place the feature within the existing mental model of the Speculation Rules API.

## Potential Scripting Entry Points to Consider

To provide a comprehensive solution that pauses all script execution, the following entry points need to be addressed. The current specification focuses on `<script>` elements, while the others are topics for further investigation and community feedback.

### Entry Points Requiring a Deferral Mechanism

These are entry points that can execute script without user interaction.

*   `<script>` elements: Includes parser-blocking, `async`, and `defer` scripts.
*   `javascript:` URLs: When used in contexts that load automatically, such as:
    *   `<iframe src="javascript:...">`
    *   `<embed src="javascript:...">`
    *   `<object data="javascript:...">`
*   `srcdoc` attribute: `<iframe srcdoc="<script>...</script>">`.
*   Inline event handlers: Handlers for events that can fire without user interaction, such as `onload` or `onerror`. The precise behavior of these is an open area for discussion.

### Entry Points Not Relevant to Prerendering

These entry points require user interaction, which is not possible in a prerendered document. Therefore, they are not a primary concern for this feature.

*   User-activated `javascript:` URLs:
    *   `<a href="javascript:...">`
    *   `<form action="javascript:...">`
*   User-initiated event handlers:
      `onclick`, `onmouseover`, `onkeydown`, etc.

## Stakeholder Feedback

*This section is a placeholder for feedback from browser vendors, web developers, and other stakeholders. The initial proposal in [GitHub issue #305](https://github.com/WICG/nav-speculation/issues/305) has received positive feedback from developers on large platforms. They think this feature is an enabler for going beyond prefetch in a lower-risk way.*

## References & acknowledgements

*   [Speculation Rules API](https://wicg.github.io/nav-speculation/)
*   [Prerendering Revamped Spec](https://wicg.github.io/nav-speculation/prerendering.html)
