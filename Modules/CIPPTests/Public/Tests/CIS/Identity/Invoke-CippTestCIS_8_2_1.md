Open federation lets any Teams tenant on the internet reach your users. Restrict to a known set of partner domains.

**Remediation Action**

```powershell
Set-CsTenantFederationConfiguration -AllowedDomains (New-CsEdgeAllowList -AllowedDomain 'partner1.com','partner2.com')
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.2.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
