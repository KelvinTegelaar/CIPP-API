MFA is the baseline control for every user account, not just admins. Microsoft data shows MFA blocks the vast majority of identity-based attacks.

**Remediation Action**

Create a Conditional Access policy:
- Users: All users (exclude break-glass accounts)
- Cloud apps: All
- Grant: Require MFA

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
