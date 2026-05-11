Forcing fresh authentication every time an Intune enrollment is initiated prevents an attacker who already has a session token from enrolling a malicious device.

**Remediation Action**

Conditional Access policy:
- Cloud apps: Microsoft Intune Enrollment (`d4ebce55-015a-49b5-a083-c84d1797ae8c`)
- Session > Sign-in frequency: Every time

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.2.11](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
