Files uploaded to SharePoint, OneDrive and Teams should be scanned by Safe Attachments to prevent malware spread within the collaboration platform.

**Remediation Action**

```powershell
Set-AtpPolicyForO365 -EnableATPForSPOTeamsODB $true -EnableSafeDocs $true -AllowSafeDocsOpen $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
