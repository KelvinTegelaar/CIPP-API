An attacker who steals a password but not the device can still register their own MFA method during initial setup, gaining persistent control. Requiring a managed device or trusted location for security info registration closes this gap.

**Remediation Action**

Conditional Access policy:
- Cloud apps > User actions: Register security information
- Grant: Require compliant device (or limit by trusted locations)

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.10](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
