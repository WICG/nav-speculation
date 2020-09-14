# Meta processing model

This is a slightly more detailed discussion of the process of finding `<meta http-equiv="Supports-Loading-Mode">` in a `text/html` response, if a prerendering loading mode is being used but the `Supports-Loading-Mode` response header was absent.

There are a few goals here:

1. Be unsurprising to the author. To the extent reasonable, the meta tag should be parsed in the same way (including encoding) that it will when the HTML document fully loads.
1. Be simple and efficient for implementers, avoiding strange corner cases where possible.
1. Encourage putting this declaration very early in the document.
1. Make this a pure computation of the document resource, not dependent on the scripting flag or arbitrary code execution.

It is presently a non-goal to support parsers other than the HTML parser. In particular, documents which use XML parsing (e.g., `application/xhtml+xml` documents) are not currently supported (though it would be possible to do so if this proved a significant constraint).

The proposed solution is to run the ordinary HTML parsing algorithm, including algorithms for detecting charset (but preventing or deferring any side effects of tree construction, like mandatory resource loads from `<link rel="stylesheet">`) on up to the first 4096 bytes of input. The first `<meta>` tag whose `http-equiv` attribute is an [ASCII case-insensitive][ascii-case-insensitive] match for `"Supports-Loading-Mode"` is used.

Parsing stops if the parser state ends the head section, in particular by having an insertion mode other than "initial", "before html", "before head", "in head" or "text". In addition, the following tag names also stop parsing because they add complexity not easily avoided:
* `<script>`: This tag could run arbitrary behavior which might not halt, might use `document.write` to modify the input stream, etc. For simplicity, even `<script>` tags which would not do so synchronously (i.e., `async` and `defer` scripts) are also not permitted. This could be modified later without breaking compatibility, if this proved too restrictive.
* `<noscript>`: This makes the computation dependent on the scripting flag, rather than being a pure descriptor of the document. The simplest solution is to require the declaration to appear before any `<noscript>` tag.
* `<template>`: The parsing rules for templates are fairly complicated and there is no clear reason why a template would need to appear before this `<meta>` in the document, so doing so is disallowed.

Notably not in this list are elements which do not have significant effects on parsing and whose effects are easily disregarded or deferred during scanning, such as:
* `<link>`: Fetches for stylesheets and other resources can simply occur once it's been determined whether loading can proceed for this document. There isn't a clear and compelling reason to not accept a `<meta>` appearing slightly later.
* `<style>`: This can similarly cause fetches via `@import`, but is also easily ignored until the browser decides to proceed with loading. Its effect on HTML parsing is simple and easy to support.
* `<bgsound>`: Both fetching the resource and playing the background sound are easy to ignore for later. (Also, modern browsers do not support it except for the parsing rules, anyhow.)

This is a compromise that means that this will produce the same result as actually loading the document for most cases where the declaration appears before any scripts or body content, while being simple to implement either by combining an HTML tokenizer with a radically simplified parser (since few of the complicated cases, such as foster parenting and template insertion location adjustment, can occur with these limitations), or by running an existing parser while deferring most side effects of tree construction.

Pseudocode for the former approach, after simplifying, is as follows:

1. Repeatedly take the next token until EOF:
    1. Ignore the token if it is a character token and it is one of U+0009 CHARACTER TABULATION, U+000A LINE FEED (LF), U+000C FORM FEED (FF), U+000D CARRIAGE RETURN (CR) and U+0020 SPACE, or it is a comment or DOCTYPE tag name. (None of these affect behavior in ways relevant here, including setting the quirks flag.)
    1. If the token is a start tag whose tag name is "meta" and its `http-equiv` attribute is a case-insensitive match for "Supports-Loading-Mode", then return its `content` attribute.
    1. If the token is a start tag whose tag name is "base", "basefont", "bgsound", "link", "html" or "head", then ignore it. (All of these are self-closing or simply create the `<html>` and `<head>` elements and advance the insertion mode within the set allowed.)
    1. If the token is a start tag whose tag name is "title", switch the tokenizer to the RCDATA state and ignore tokens until the matching end tag, inclusive, and continue at the next token.
    1. If the token is a start tag whose tag name is "style", switch the tokenizer to the RAWTEXT state and ignore tokens until the matching end tag, inclusive, and continue at the next token.
    1. If the token is an end tag whose tag name is "head", "body", "html" or "br", then ignore it.
    1. Otherwise, return null. (Non-whitespace text, a tag name that ends the head section, or one of the three problematic tag names above, has been encountered.)

Dynamic changes to the document and `<meta>` tags appearing elsewhere do not affect processing. A script may remove the `<meta>` element at runtime, but doing so has no effect.

[ascii-case-insensitive]: https://infra.spec.whatwg.org/#ascii-case-insensitive