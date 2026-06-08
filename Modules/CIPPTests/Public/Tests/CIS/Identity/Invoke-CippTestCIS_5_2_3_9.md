Account lockout duration determines how long an account stays locked out after exceeding the lockout threshold, and therefore how long an attacker must wait before resuming attempts. A duration of at least 60 seconds, combined with a reasonable threshold, reduces the total number of failed sign-in attempts a malicious actor can perform over time while limiting inconvenience to legitimate users.

**Remediation Action**

Microsoft Entra > Authentication methods > Password protection: set Lockout duration in seconds to 60 or higher, then save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.3.9](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
