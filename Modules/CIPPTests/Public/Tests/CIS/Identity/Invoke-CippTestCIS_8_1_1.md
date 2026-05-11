Teams can attach files from third-party storage providers. Disable any provider not in the approved list.

**Remediation Action**

```powershell
Set-CsTeamsClientConfiguration -Identity Global -AllowDropbox $false -AllowBox $false -AllowGoogleDrive $false -AllowShareFile $false -AllowEgnyte $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.1.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
