# Privacy-Preserving Prefetch Proxy Servers

# Abstract

Privacy-Preserving Prefetch Proxy Servers are Internet-accessible servers that provide web browsers with a means of prefetching web resources while preserving user privacy during a speculative navigation.

# 1. Introduction

Web developers use **speculation rules** to instruct the browser to perform navigation actions like prefetching or prerendering before navigation starts, speeding up subsequent navigations. Speculation rules can include arrays of speculation rule requirements. The only presently-defined requirement is the string "anonymous-client-ip-when-cross-origin" (ACIWCO). When defined in a rule, ACIWCO requires a **cross-origin prefetch IP anonymization policy** to be set for the prefetch candidate corresponding to the rule.

A prefetch is cross-origin when the referring page’s origin and the target origin are distinct. IP anonymization is commonly understood to mean that the user agent should hide or mask the external IP address of the client \[[IP-PRIVACY](https://datatracker.ietf.org/doc/html/draft-irtf-pearg-%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20ip-address-privacy-considerations-01)\]. IP anonymization may be requested by a referring page to avoid leaking client PII when performing a prefetch, and the browser is required to anonymize the request or not execute it.

This draft is a companion document to the WICG proposal for **referrer-provided prefetch proxies**, an architectural model that allows sites to run their own IP anonymizing prefetch proxies. The primary benefits of sites running their own IP anonymizing proxies are:

* Privacy  
  * The proxy doesn’t learn additional information about the client from its prefetch requests beyond what the referrer document already learned in the initial navigation  
* Cost alignment  
  * Sites that want performance improvements can operate a proxy  
  * Browsers aren’t obligated to provide IP anonymization for all sites that want it

## 1.1 Scope

This document provides a specification for the client-server protocol between a client web browser and a prefetch proxy server that allows the client to prefetch web resources from remote origin servers through the proxy server, in order to protect client PII.

## 1.2 Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 \[RFC2119\] \[RFC8174\] when, and only when, they appear in all capitals, as shown here.

# 2. Client-Server Protocol

## 2.1 Overview

The protocol between the client browser (Client) and proxy server (Server) assumes that the proxy server is already a trusted server. The proxy is either provided by the web browser’s IP anonymization implementation or by the referrer site.

The proxy server MUST support the following connection types: HTTP CONNECT \[[HTTP](https://www.rfc-editor.org/rfc/rfc9110.html#name-connect)\] or [CONNECT-UDP](https://www.rfc-editor.org/rfc/rfc9298). Connections MUST be protected with TLS so the server cannot directly inspect client-origin traffic.

In this document we refer to the Server as a single-hop proxy server. Server operators MAY implement the Server as a multi-hop proxy as long as their architecture can function as a single logical proxy.

The protocol involves the following steps, which also apply for CONNECT-UDP:

1. The Client constructs a CONNECT request to a Server for an Origin.  
2. The Client sends a CONNECT request to the Server.  
3. The Server handles the CONNECT request. If the request is successful, the Server establishes a CONNECT tunnel to the Origin.  
4. The Client establishes a TLS connection to the Origin inside the CONNECT tunnel.  
5. The Client requests the Resource from the Origin.

## 2.2 Client Requests

To start the client-server protocol, the Client must initially know the following:

* Hostname of the Server  
* URL of an Origin Resource to prefetch  
* Authorization tokens to be validated by the Server

The Client MUST send a HTTP CONNECT or CONNECT-UDP request to the Server using one of the following HTTP protocol versions: 1.1, 2, or 3\. If using CONNECT, the Client MUST use HTTPS.

If the Client’s prefetch request contains a proxy authorization token, the token MUST be passed to the Server via a “Proxy-Authorization” header using the “Bearer” authentication scheme.

When the Client requests the resource from the Origin, the Client MUST send a header field indicating the purpose of the request is speculative navigation / a prefetch.

## 2.3 Server Responses

The Server MUST accept a HTTPS CONNECT or CONNECT-UDP request from the Client. Servers MUST support one of: HTTP/1.1, HTTP/2, or HTTP/3. The Server MUST NOT accept an unencrypted CONNECT request.

The Server’s response protocol involves the following steps:

1. The Server checks the Client’s authorization token from the “Proxy-Authorization” header and returns a HTTP error if it’s invalid.  
2. The Server will resolve the Origin’s Host or Authority provided in the CONNECT request header fields.  
3. The Server will look up the Origin’s traffic-advice configuration.  
4. The Server either establishes the CONNECT tunnel to the Origin or returns a HTTP error to the Client.  
5. The Server sends a Successful response and switches to tunnel mode.  
6. Server forwards traffic between the Client and Origin and closes the tunnel as specified in RFC 9110\.

# 3. Server Requirements

## 3.1 Abuse Prevention

Servers MUST take appropriate measures to prevent abusive traffic, to block denial-of-service attacks against Origins, and to avoid becoming a general IP anonymizing proxy.

The following measures are RECOMMENDED:

* Site-issued proxy authorization tokens that are validated by Servers  
* Client IP-based rate limiting  
* Enforcing a per-session byte transfer ratio, where origins are expected to send more data than clients  
* Limiting prefetch session duration  
* Limiting total connections to servers across all users  
* Blocklisting abusive IPs

## 3.2 Geolocation

The operator of the Server MAY serve different geographic jurisdictions from different egress IP pools. The operator of the Server MUST publish a geofeed \[[GEOFEED](https://datatracker.ietf.org/doc/rfc8805/)\] containing the Server’s egress IP to physical location mappings.

## 3.3 Privacy

The Server’s privacy goals are:

* Origins should not be able to learn anything about the user, through cookies, IP address, cache \[non\]usage, etc, until the prefetched resource is used.  
* Users cannot be fingerprinted via IP address, TCP connections, User-Agent header, Accept-Language header, or Client Hints.  
* The proxy and referrer cannot learn additional information about the user, outside of what is already learned through the user’s initial navigation to the referrer page.

Servers MUST NOT send cookies or other client PII to Origins if the CONNECT request contains them. Servers MUST NOT share client PII with Origins. Servers SHOULD minimize logging to what is necessary for abuse prevention.

## 3.4 Traffic Control

Origins can configure the amount of prefetch traffic they want to receive in their site’s /.well-known/traffic-advice file. This file is served with the application/trafficadvice+json MIME type.

Servers MUST respect the “fraction” and “disallow” fields configured for “user\_agent”: “prefetch-proxy” in the traffic-advice file. Servers SHOULD cache sites’ traffic-advice files with standard HTTP cache semantics.

# 4. Security Considerations

Servers should take all necessary precautions to avoid relaying abusive, fraudulent, and invalid traffic through their proxy servers. Another goal is to avoid being used as an open proxy for any Internet user.

# 5. IANA Considerations

This document has no IANA actions.

# 6. References

* \[CONNECT\] Khare, R. and S. Lawrence, "Upgrading to TLS Within HTTP/1.1", RFC 2817, DOI 10.17487/RFC2817, May 2000, \<[https://www.rfc-editor.org/rfc/rfc2817](https://www.rfc-editor.org/rfc/rfc2817)\>.  
* \[CONNECT-UDP\] Schinazi, D., "Proxying UDP in HTTP", RFC 9298, DOI 10.17487/RFC9298, August 2022, \<[https://www.rfc-editor.org/rfc/rfc9298](https://www.rfc-editor.org/rfc/rfc9298)\>.  
* \[GEOFEED\] [https://datatracker.ietf.org/doc/rfc8805/](https://datatracker.ietf.org/doc/rfc8805/)   
* \[HTTP\] [https://www.rfc-editor.org/rfc/rfc9110.html](https://www.rfc-editor.org/rfc/rfc9110.html#name-connect)  
* \[IP-PRIVACY\] Finkel, M., Lassey, B., Iannone, L., and B. Chen, "IP Address Privacy Considerations", Work in Progress, Internet-Draft, draft-irtf-pearg-ip-address-privacy-considerations-01, 23 October 2022, \<[https://datatracker.ietf.org/doc/html/draft-irtf-pearg-ip-address-privacy-considerations-01](https://datatracker.ietf.org/doc/html/draft-irtf-pearg-ip-address-privacy-considerations-01)\>.

# 7. Acknowledgments

# 8. Author’s Address

Robert Liu  
Google LLC  
355 Main St  
Cambridge, MA 02142  
United States of America  
Email: [elburrito@chromium.org](mailto:elburrito@chromium.org) 
