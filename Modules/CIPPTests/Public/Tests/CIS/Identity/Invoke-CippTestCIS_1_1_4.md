Administrative accounts that hold productivity licenses (Exchange Online, SharePoint, Teams) expose far more attack surface than identity-only accounts. A single phishing email or a malicious browser extension can compromise an admin if their account also reads mail and browses Teams.

**Remediation Action**

1. Strip productivity licenses (Exchange, SharePoint, Teams, Office) from administrative accounts.
2. Assign only an Entra ID P1 / P2 (or EMS) license, sufficient for management activity.
3. Block sign-in to mailbox / OWA / Teams for these accounts via Conditional Access if licenses cannot be removed.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.1.4](https://www.cisecurity.org/benchmark/microsoft_365)
- [Tiered admin model](https://learn.microsoft.com/security/privileged-access-workstations/privileged-access-access-model)

<!--- Results --->
%TestResult%
