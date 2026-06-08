Default-on recording captures meetings that may include sensitive content (HR, M&A, customer data). Default off and grant recording rights only where there is a business need.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowCloudRecording $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.5.9](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
