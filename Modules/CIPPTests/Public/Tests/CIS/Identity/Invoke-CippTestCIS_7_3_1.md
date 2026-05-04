Microsoft scans SharePoint and OneDrive content for malware. Without `DisallowInfectedFileDownload`, infected files can still be downloaded — Microsoft only flags them.

**Remediation Action**

```powershell
Set-SPOTenant -DisallowInfectedFileDownload $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.3.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
