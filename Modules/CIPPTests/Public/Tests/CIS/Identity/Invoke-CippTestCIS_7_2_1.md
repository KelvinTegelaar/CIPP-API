Legacy auth into SharePoint bypasses MFA. Disable to ensure modern OAuth2 flows.

**Remediation Action**

```powershell
Set-SPOTenant -LegacyAuthProtocolsEnabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
