Without on-prem password protection, weak passwords created in AD never reach Microsoft's banned-password engine. Enforce mode rejects bad passwords at change time on every domain controller.

**Remediation Action**

1. Install the Entra Password Protection proxy and DC agent on every domain controller.
2. Microsoft Entra > Authentication methods > Password protection: Enable password protection on Windows Server Active Directory + Mode = Enforced.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.3.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
