CIS L2 hardening: instead of requiring MFA on risky sign-ins, block them outright. This trades a small productivity hit for high security on the most-targeted accounts.

**Remediation Action**

Conditional Access policy:
- Users: privileged roles (or all users for L2)
- Conditions > Sign-in risk: Medium, High
- Grant: Block

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.8](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
