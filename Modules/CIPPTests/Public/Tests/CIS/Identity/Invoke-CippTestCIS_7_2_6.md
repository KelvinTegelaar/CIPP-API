Restrict external sharing to a known list of partner domains so users can't share with unknown organisations.

**Remediation Action**

```powershell
Set-SPOTenant -SharingDomainRestrictionMode AllowList -SharingAllowedDomainList 'partner1.com partner2.com'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
