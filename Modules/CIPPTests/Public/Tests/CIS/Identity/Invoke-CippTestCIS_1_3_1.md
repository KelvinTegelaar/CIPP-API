Forced password rotation drives users to predictable patterns (Summer2025!, Summer2026!) that are easier for attackers to guess. NIST SP 800-63B and Microsoft now recommend never expiring passwords, paired with strong MFA and breach detection.

**Remediation Action**

```powershell
Update-MgDomain -DomainId <domain> -PasswordValidityPeriodInDays 2147483647 -PasswordNotificationWindowInDays 14
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.1](https://www.cisecurity.org/benchmark/microsoft_365)
- [Set passwords to never expire](https://learn.microsoft.com/microsoft-365/admin/manage/set-password-to-never-expire)

<!--- Results --->
%TestResult%
