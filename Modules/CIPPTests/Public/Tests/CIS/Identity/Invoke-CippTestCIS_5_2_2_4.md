Long-lived session tokens stolen from an administrator's browser provide an attacker with persistent privileged access. Forcing frequent re-authentication and disabling browser persistence shrinks that window.

**Remediation Action**

Conditional Access policy targeting privileged roles with:
- Session > Sign-in frequency: 4 hours (or less)
- Session > Persistent browser: Never persistent

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
