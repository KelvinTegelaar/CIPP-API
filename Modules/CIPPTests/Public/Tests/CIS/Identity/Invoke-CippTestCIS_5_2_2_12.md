The device code flow is the most common phishing vector now in use against M365 — attackers send a victim a code and a URL and exfiltrate the resulting tokens. Block the flow unless explicitly required.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass and any service accounts that need device code flow)
- Conditions > Authentication flows > Transfer methods: Device code flow
- Grant: Block

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.12](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
