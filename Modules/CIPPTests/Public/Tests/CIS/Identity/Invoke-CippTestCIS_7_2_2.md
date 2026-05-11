Azure AD B2B integration ensures every external user accessing SharePoint / OneDrive is a managed guest, subject to Conditional Access and Access Reviews — not an ad-hoc external sharing identity.

**Remediation Action**

```powershell
Set-SPOTenant -EnableAzureADB2BIntegration $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
