Sign-in risk reflects per-session anomalies (impossible travel, malicious IP, anonymous proxy). A CA policy that requires MFA on Medium+ risk catches in-progress attacks.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass)
- Conditions > Sign-in risk: Medium, High
- Grant: Require MFA

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.7](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
