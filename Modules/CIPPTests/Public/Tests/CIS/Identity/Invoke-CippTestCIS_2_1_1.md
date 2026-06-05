Safe Links scans URLs in email, Teams, and Office documents at click time, blocking access to malicious URLs even if they were safe at delivery.

**Remediation Action**

```powershell
New-SafeLinksPolicy -Name 'Default Safe Links' -EnableSafeLinksForEmail $true -EnableSafeLinksForTeams $true -EnableSafeLinksForOffice $true -ScanUrls $true -TrackClicks $true -AllowClickThrough $false -DisableUrlRewrite $false -DeliverMessageAfterScan $true -EnableForInternalSenders $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 2.1.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
