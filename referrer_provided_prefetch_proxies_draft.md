# Explainer: Referrer-Provided Prefetch Proxies

This proposal is an early design sketch by the Chrome Prefetch Proxy team to describe the problem below and solicit feedback on the proposed solution. It has not been approved to ship in Chrome.

This proposal introduces a referrer-provided prefetch proxy requirement for speculation rules, allowing sites to implement a private prefetch proxy and specify it in speculation rules scripts. It also introduces a token-based authentication requirement for these proxy requests.

## Proponents
- Chrome Prefetch Proxy team

## Participate
- https://github.com/WICG/nav-speculation/issues

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Introduction](#introduction)
- [Goals](#goals)
- [Non-goals](#non-goals)
- [User research](#user-research)
- [Use cases](#use-cases)
- [Proposed solution: referrer-provided prefetch proxies](#proposed-solution-referrer-provided-prefetch-proxies)
  - [New speculation rule requirements](#new-speculation-rule-requirements)
  - [Parsing model](#parsing-model)
  - [Processing model](#processing-model)
  - [Creating an IP anonymized connection](#creating-an-ip-anonymized-connection)
- [Detailed design discussion](#detailed-design-discussion)
  - [Specifying a standard for privacy-preserving prefetch proxies](#specifying-a-standard-for-privacy-preserving-prefetch-proxies)
  - [Token handling algorithm for CONNECT requests](#token-handling-algorithm-for-connect-requests)
- [Considered alternatives](#considered-alternatives)
  - [Status quo: browser-provided proxies only](#status-quo-browser-provided-proxies-only)
  - [Alternatives for specifying a referrer-provided prefetch proxy](#alternatives-for-specifying-a-referrer-provided-prefetch-proxy)
  - [Alternatives for authenticating to a referrer-provided prefetch proxy](#alternatives-for-authenticating-to-a-referrer-provided-prefetch-proxy)
  - [OHTTP-based approach](#ohttp-based-approach)
- [Security and Privacy Considerations](#security-and-privacy-considerations)
- [Stakeholder Feedback / Opposition](#stakeholder-feedback--opposition)
- [References & acknowledgements](#references--acknowledgements)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Introduction

Web developers use **speculation rules** to instruct the browser to perform navigation actions like prefetching or prerendering before navigation starts, speeding up subsequent navigations. Speculative navigations can be same-origin or cross-origin and the former has minimal privacy concerns. However, to avoid leaking information when cross-origin prefetching, the user’s IP address must be anonymized to prevent the origin from learning the client's IP address and potentially re-identifying the user.

IP anonymization [is understood to mean that the user agent should hide or mask the external IP address of the client](https://github.com/WICG/nav-speculation/blob/main/anonymous-client-ip.md). IP anonymization may be requested by a referring page to avoid leaking client PII when performing a cross-origin prefetch. This requirement is expressed as a [speculation rule requirement](https://html.spec.whatwg.org/#speculation-rule-requirement): `"anonymous-client-ip-when-cross-origin"` (**ACIWCO**). Speculation rules can include arrays of speculation rule requirements and ACIWCO is the only one yet defined. When set in a rule, ACIWCO requires a **cross-origin prefetch IP anonymization policy** to be set for the prefetch candidate corresponding to the rule.

Today, [the spec](https://html.spec.whatwg.org/multipage/speculative-loading.html#speculative-loading:~:text=If%20rule%27s%20requirements%20contains%20%22anonymous%2Dclient%2Dip%2Dwhen%2Dcross%2Dorigin%22%2C%20then%20set%20anonymizationPolicy%20to%20a%20cross%2Dorigin%20prefetch%20IP%20anonymization%20policy%20whose%20origin%20is%20document%27s%20origin.) asks browsers to implement a cross-origin prefetch IP anonymization policy. This isn’t ideal for a few reasons: privacy concerns limit the use of browser-provided prefetch proxies; costs are a significant factor for vendors and referrers don’t share the cost of supporting their speculation rules; and site owners might not trust the browser's proxy.

This explainer introduces a referrer-provided prefetch proxy, in order to get public feedback on its feasibility for standardization. In the **referrer-provided prefetch proxy** architecture, the website initiating the prefetch (the referrer) operates its own privacy-preserving proxy server and specifies it in the page’s speculation rules script. This aligns the proxy trust model, avoids introducing a third-party service, and shifts the operational cost to the party that directly benefits from faster navigation.

## Goals

* Enable any referring site to offer privacy-preserving cross-origin prefetch to its users without relying on browser-provided proxy infrastructure.  
* Give origins control over prefetch traffic using existing mechanisms: .well-known/traffic-advice configuration, Sec-Purpose headers.  
* Specify how referrer-provided proxies can be privacy-preserving.  
* Specify how cross-origin prefetches can avoid leaking additional information about clients.

## Non-goals

* This proposal is scoped to cross-origin prefetch only. Same-origin prefetch and prerendering are out of scope.  
* This proposal does not deprecate the ability of user agents to operate IP anonymizing services for cross-origin prefetching. That will remain an implementation option.

## User research

Site owners have shown significant performance gains from using Speculation Rules. For example:
* [Google Search reduced LCP for clicks from Search by \~60 ms](https://developer.chrome.com/blog/search-speculation-rules)
* [Shopify reduced loading metrics by 130-180 ms](https://performance.shopify.com/blogs/blog/speculation-rules-at-shopify)
* [Etsy saw a 20-24% improvement in FCP and LCP](https://www.etsy.com/codeascraft/search-prefetching-performance)

These findings suggest that enabling cross-origin prefetch in a more scalable and accessible way could yield benefits for the web ecosystem.

## Use cases

A site owner wants to speed up cross-origin navigations on their pages. They want to get the same performance improvement on cross-origin navigation as they do on same-origin navigation.

Their current implementation options are limited:
* Use Speculation Rules API or another means of speculatively loading resources without a privacy-preserving proxy. **This exposes client IP addresses to 3P origins.**  
* Use Speculation Rules API with the ACIWCO requirement. The satisfaction of this requirement is left up to the UA implementation, which might not support ACIWCO. If the UA doesn’t support ACIWCO, it [must not execute any rules with that requirement](https://wicg.github.io/nav-speculation/prefetch.html#ref-for-prefetch-record-anonymization-policy%E2%91%A0). Additionally, since this introduces a third-party service run by the browser-vendor, the UA may require additional opt-ins ([Chrome, the only browser currently running such a proxy [requires users to enable the "Extended preloading" mode in Chrome's [preload settings](https://support.google.com/chrome/answer/1385029?&co=GENIE.Platform%3DAndroid)](https://developer.chrome.com/blog/private-prefetch-proxy#referrers:~:text=to%20allow%20other%20sites%20to%20preload%20navigations%20through%20Google%20servers%2C%20users%20need%20to%20select%20the%20%22Extended%20preloading%22%20mode%20in%20Chrome%27s%20preload%20settings.)).

The site owner cannot control how the ACIWCO requirement is satisfied for their speculation rule. This proposal is to give them control by letting them bring their own proxy.

Sites may want to implement their own prefetch proxy if:
* Browser-provided implementations don't exist. Referrer-provided prefetch proxies can support private cross-origin prefetch in every browser that implements the feature.
* Sites may not want to send prefetch traffic to another company’s proxy infrastructure.
* The browser-provided implementation requires a user opt-in for privacy reasons. Having the same party operate the referrer page and proxy prevents additional information leakage to the proxy operator, which may obviate the need for user opt-in.
* The site wants more direct control over prefetch usage, cost, or infrastructure.
* Sites may already have the infrastructure in place to operate a prefetch proxy.

## Proposed solution: referrer-provided prefetch proxies

We propose the **referrer-provided prefetch proxy** architecture, where the referring website operates its own privacy-preserving proxy server and specifies it in the speculation rules.

### New speculation rule requirements

We propose adding two new speculation rule requirements at the rule level:

* `“use-referrer-provided-prefetch-proxy”`, which instructs the browser to use a specific privacy-preserving prefetch proxy  
* `“prefetch-proxy-authorization-tokens”`, which instructs the browser to use authorization tokens provided in the rule when connecting to a specified privacy-preserving prefetch proxy.

When one of the above requirements is set, its respective key must be set with an appropriate value in the speculation rule JSON object:

* `“referrer\_provided\_prefetch\_proxy”`: Valid URL string  
* `“proxy\_authorization\_tokens”`: List of JavaScript strings

These keys are parsed into corresponding items in the speculation rule struct:

* Referrer provided prefetch proxy URL, a URL  
* Proxy authorization tokens, an ordered set of [strings](https://infra.spec.whatwg.org/#strings)

Speculation rules with the new requirements are only well-defined when:

* **All three `requirements` are set:** UA must use the referrer-provided prefetch proxy and authenticate with the provided authorization tokens. If this connection does not succeed, the UA may fall back to its own IP anonymization implementation.  
* **Only the two new `requirements` are set, without ACIWCO:** UA must use the referrer-provided prefetch proxy and authenticate with the provided authorization tokens. If this connection does not succeed, the UA stops execution of this speculation rule.  
* **Only ACIWCO is set:** No change from current spec – UA either provides IP anonymization for this prefetch, or it [must not execute the speculation rule](https://github.com/WICG/nav-speculation/blob/main/anonymous-client-ip.md).  
* **No requirements are set:** UA will not use a proxy to prefetch this speculation rule candidate.

After this change, the meaning of the existing **ACIWCO** `requirement` will change when the two additional new `requirement`s are set. Presently, ACIWCO is a directive to always use the UA’s IP-anonymization implementation. With this change **ACIWCO** will be used as a fallback when the two new `requirement`s are set, not as the first-choice proxy, and only used if the connection to the referrer-provided proxy does not succeed.

Example:

```json
<script type="speculationrules">
{
  "prefetch": [
    {
      "urls": ["bar.com"],
      "requires": [
        "anonymous-client-ip-when-cross-origin",
        "use-referrer-provided-prefetch-proxy",
        "prefetch-proxy-authorization-tokens"
      ],
      "referrer_provided_prefetch_proxy": "https://prefetch.bar.com",
      "proxy_authorization_tokens": ["EXAMPLE_TOKEN"]
    }
  ]
}
</script>
```

### Parsing model

A UA will parse the new keys by:

1. Let *referrerProvidedPrefetchProxyURL* be an empty URL.  
2. If input\["referrer\_provided\_prefetch\_proxy"\] exists:  
   1. If input\["referrer\_provided\_prefetch\_proxy"\] is not a valid URL string:  
      1. The user agent may report a warning to the console indicating that the referrer-provided URL was not understood.  
      2. Return null.  
   2. Set *referrerProvidedPrefetchProxyURL* to input\["referrer\_provided\_prefetch\_proxy"\].  
3. Let *proxyAuthorizationTokens* be an empty set.  
4. If input\["proxy\_authorization\_tokens"\] exists, append input\["proxy\_authorization\_tokens"\] to *proxyAuthorizationTokens*.

### Processing model

We will add the following items to the definition of a [cross-origin prefetch IP anonymization policy struct](https://html.spec.whatwg.org/multipage/speculative-loading.html#cross-origin-prefetch-ip-anonymization-policy):

* Referrer-provided prefetch proxy, a URL  
* Proxy authorization tokens, an ordered set of (ASCII strings?)

A browser would process a speculation rule with the three requirements “anonymous-client-ip-when-cross-origin”, “cross-origin-prefetch-proxy”, and “prefetch-proxy-authorization-tokens” by:

1. If the origin is not cross-origin to the referrer:  
   1. The user agent should not use *referrerProvidedPrefetchProxyURL* as the prefetch proxy.  
2. The user agent must use *referrerProvidedPrefetchProxyURL* as the prefetch proxy.  
   1. Set parameters in the prefetch record struct.  
   2. Start a referrer-initiated navigational prefetch.

### Creating an IP anonymized connection

We will define an algorithm for browsers to create an IP anonymized connection. The algorithm will:

* Require browsers to start an encrypted HTTP CONNECT tunnel session with the proxy server  
* Specify headers for the CONNECT request, such as Host (of the origin) and Proxy-Authorization (for authorization tokens)  
* Require the proxy URL to be same-site to the referrer document  
* Require browsers to use an isolated network context that does not reveal previous browser state  
* Require browsers to use the following headers for connections to the proxy and tunneled connections to the origin: Sec-Purpose: “prefetch; anonymous-client-ip”

We will also define proxy server requirements in a separate document formatted as an Internet Draft. This draft will:

* Specify the server side of the client-server protocol for prefetch IP anonymization  
* Define privacy and security requirements for servers  
* Formalize the ./well-known/traffic-advice file for site developers  
* Require prefetch servers to respect ./well-known/traffic-advice files

**See [Referrer-provided Prefetch Proxy Server Requirements](referrer_provided_prefetch_proxy_server_requirements.md) for more details.**

## Detailed design discussion

### Specifying a standard for privacy-preserving prefetch proxies

* **Should the referrer-provided proxy take precedence over the UA IP anonymization implementation (ACIWCO) when all three speculation rule requirements are listed in a rule?**  
  Yes: the site is explicitly providing a resource for the UA.
* **What network protocol should UAs use to connect to a proxy?**  
  An encrypted version of HTTP CONNECT (HTTPS, H/2, H/3). Connection should be encrypted from the UA to the proxy and from the proxy to the origin server.  
* **Privacy standards for proxy implementations**  
  Additional privacy requirements are discussed in the attached document on proxy server requirements.

### Token handling algorithm for CONNECT requests

* **How do site developers control which tokens are used by a UA in a specific request?**  
  Options: UAs pick a token at random from the list of authorization tokens, or UAs use the ordering of the list. The latter doesn't seem great as there are complex speculation rules with no ordering guarantees on execution. For example, on-hover speculation rules depend on user input. If a site developer must control which tokens are used for a proxy request, they can provide a single token for all proxy requests.
* **What happens if a speculation rules JSON document doesn’t provide exactly as many tokens as there are prefetch candidates?**  
  Proposal: UA will select and remove a token at random from the ordered set of tokens and use that token for a CONNECT request. If the set is empty, the “create navigation params” algorithm should fail and print a warning to the console.  
* **What if a site developer wants to use the same token for every prefetch execution?**  
  Proposal: UAs will support this. Speculation rules documents can specify this behavior by providing only one token in the rule. In this case, UAs should not remove the token from the set when executing a prefetch. UAs will consume tokens from the set when there are multiple tokens provided.

## Considered alternatives

### Status quo: browser-provided proxies only

* Using a single proxy server reveals information about the target sites to the proxy.
* Using a two-hop proxy chain hides more information but is more complex.
* Keeping this as an opt-in, off-by-default for privacy reasons severely limits its use.
* Expensive for browsers to maintain and offer.  
* Trade-off between privacy and cost: using a single proxy server reveals information about the target sites to the proxy; using a two-hop proxy chain hides more information but is more expensive.

### Alternatives for specifying a referrer-provided prefetch proxy

* We considered putting the proxy configuration in the speculation rule set level, but decided on the per-rule level for better flexibility and alignment with existing requirements.

### Alternatives for authenticating to a referrer-provided prefetch proxy

* We explored mechanisms other than auth tokens, but tokens provide a simple and effective way for sites to manage access and cost.

### OHTTP-based approach

We ruled out Oblivious HTTP as an alternative proxying protocol because OHTTP is message-oriented rather than connection-oriented and thus easier to MITM. Connection-oriented protocols establish a TLS connection from the UA to the origin and ensure that the proxy server can’t tamper with the HTTP request in the CONNECT tunnel.

## Security and Privacy Considerations

Prefetching web pages has the risk of exposing user information through speculative navigations. We consider the following parties in our privacy model: User agent, Referrer page, Private prefetch proxy, and Origin server.

The goal of this privacy model is to define principles that result in the least information being available to the proxy and the origin server.

First, **we propose that the referrer-provided proxy must be same-site to the referrer page.**. If the referrer and proxy are same-site, then the proxy operator has all the information that the referrer received. No additional user information is sent to the proxy that the referrer didn't already receive. Allowing non same-site proxies reintroduces many of the issues with the original UA implementation.

Second, **the user agent should not selectively send prefetch requests based on client PII, or include PII in prefetch requests** to avoid leaking information about PII. When the referrer and the proxy are run by the same party, that party can identify which prefetches are requested by the referring page and not sent to the proxy. This can indirectly leak PII that the user agent uses in the decision to prefetch, like the presence of a cookie for a particular site. Including PII in prefetch requests, like cookies or service workers, may directly leak user identity to origin servers.

See the [**Security and Privacy Questionnaire**](#security-and-privacy-questionnaire) section below for more information.

## Stakeholder Feedback / Opposition

* **Firefox:** No public position. Firefox engineers originally suggested this feature in March 2025: [https://github.com/WICG/nav-speculation/issues/368](https://github.com/WICG/nav-speculation/issues/368).  
* **Safari:** No public position.  
* **Edge:** No public position.

## References & acknowledgements

* [HTML Standard, “Speculative loading”](https://html.spec.whatwg.org/multipage/speculative-loading.html#speculative-loading)
* [Prefetch draft CG report](https://wicg.github.io/nav-speculation/prefetch.html)
* ["Private Prefetch Proxy Explained"](https://github.com/buettner/private-prefetch-proxy), [Michael Buettner](https://www.github.com/buettner)   
* Thanks to [Dominic Farolino](https://www.github.com/domfarolino) for the spec mentorship\!

## Security and Privacy Questionnaire

### 2.1 What information does this feature expose, and for what purposes?

This feature exposes information about speculative navigations requested by a site to a prefetch proxy server that is operated by the same site. The following information is newly exposed to the first-party proxy operator:

* Which speculation rule prefetches are executed  
* Speculation rule timing: when are rules executed

This feature does not expose information to third parties: prefetch proxies are required to be same-site to the referrer document. 

### 2.2 Do features in your specification expose the minimum amount of information necessary to implement the intended functionality?

Yes: a proxy server is required to implement the IP anonymization functionality that is specified in the new speculation rules requirements.

### 2.3 Do the features in your specification expose personal information, personally-identifiable information (PII), or information derived from either?

No.

### 2.4 How do the features in your specification deal with sensitive information?

This feature requires a prefetch proxy to be same-site to the referring document so that no information is exposed to any party that the party could not already access. All other restrictions of cross-origin prefetching remain in effect.

### 2.5 Does data exposed by your specification carry related but distinct information that may not be obvious to users?

No. Prefetch proxies are required to not expose user metadata or fingerprinting vectors to origins, including but not limited to client cookies.

### 2.6 Do the features in your specification introduce state that persists across browsing sessions?

No. Prefetched documents will be discarded once the user navigates away from the primary page or closes the tab.

### 2.7 Do the features in your specification expose information about the underlying platform to origins?

No.

### 2.8 Does this specification allow an origin to send data to the underlying platform?

No.

### 2.9 Do features in this specification enable access to device sensors?

No.

### 2.10 Do features in this specification enable new script execution/loading mechanisms?

No. It changes how existing speculationrules scripts are parsed by introducing new speculation rules requirements, but does not introduce new execution or loading mechanisms.

### 2.11 Do features in this specification allow an origin to access other devices?

No.

### 2.12 Do features in this specification allow an origin some measure of control over a user agent’s native UI?

No.

### 2.13 What temporary identifiers do the features in this specification create or expose to the web?

Use of a prefetch proxy should not be considered a temporary identifier because proxies aggregate multiple users’ traffic through their egress IP ranges and further anonymize prefetch requests.

### 2.14 How does this specification distinguish between behavior in first-party and third-party contexts?

This feature aims to restrict sites from sending data from first-party to third-party contexts by introducing a same-site requirement for prefetch proxies. The provided prefetch proxy must be same-site to the referrer document.

### 2.15 How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

No change in behavior between standard and private/incognito modes.

### 2.16 Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

Yes.

### 2.17 Do features in your specification enable origins to downgrade default security protections?

No, it inherits all the security and privacy protections of standard prefetching.
