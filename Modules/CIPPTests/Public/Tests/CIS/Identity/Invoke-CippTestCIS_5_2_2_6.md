Identity Protection's User Risk score reflects credential leaks, anomalous behaviour, and other compromise indicators. Acting on User Risk = High by forcing password change blunts credential-theft attacks.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass)
- Conditions > User risk: High
- Grant: Require password change + MFA

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
