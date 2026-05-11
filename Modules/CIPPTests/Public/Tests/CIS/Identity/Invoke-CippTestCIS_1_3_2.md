A long-lived session token on an unmanaged device is a high-value target. CIS recommends Conditional Access enforce a sign-in frequency of 3 hours or less for these devices.

**Remediation Action**

Create a Conditional Access policy:
- Users: All users (or pilot group)
- Cloud apps: All
- Conditions: Device filter — exclude compliant / hybrid joined
- Session: Sign-in frequency 3 hours, persistent browser = never

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.2](https://www.cisecurity.org/benchmark/microsoft_365)
- [Configure sign-in frequency](https://learn.microsoft.com/entra/identity/conditional-access/concept-session-lifetime)

<!--- Results --->
%TestResult%
