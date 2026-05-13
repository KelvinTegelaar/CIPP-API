When the default link type is "Anyone with the link" users accidentally publish content to the internet. Default to Direct (specific people) so anonymous links are an explicit choice.

**Remediation Action**

```powershell
Set-SPOTenant -DefaultSharingLinkType Direct
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.7](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
