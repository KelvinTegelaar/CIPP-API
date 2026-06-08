Per-user MFA (the legacy setting on a user object) bypasses Conditional Access logic and creates inconsistent enforcement. Microsoft and CIS recommend disabling per-user MFA and managing MFA exclusively through Conditional Access.

**Remediation Action**

Use Graph or the legacy `Set-MsolUser` to set `StrongAuthenticationRequirements` to an empty array on every user.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.2.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
