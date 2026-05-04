Legacy authentication protocols (POP, IMAP, SMTP AUTH, EAS, older clients) cannot enforce MFA. Almost all password-spray and credential-stuffing attacks target these protocols.

**Remediation Action**

Conditional Access policy with:
- Users: All users (exclude break-glass)
- Cloud apps: All
- Conditions > Client apps: Exchange ActiveSync clients + Other clients
- Grant: Block

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
