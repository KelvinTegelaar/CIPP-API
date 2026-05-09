Modern auth (OAuth2) is required for MFA enforcement on Outlook 2013/2016 connecting to Exchange Online.

**Remediation Action**

```powershell
Set-OrganizationConfig -OAuth2ClientProfileEnabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.5.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
