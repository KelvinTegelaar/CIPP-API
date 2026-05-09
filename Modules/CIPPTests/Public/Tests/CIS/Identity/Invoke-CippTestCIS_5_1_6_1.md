An open guest invitation policy lets users invite anyone with any email — a frequent path for data exfiltration via shared links to attacker-controlled mailboxes. Restrict invitations to known partner domains.

**Remediation Action**

Configure `invitationsAllowedAndBlockedDomainsPolicy` on the cross-tenant access / B2B settings, with an explicit `allowedDomains` allowlist (or `blockedDomains` denylist).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.6.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
