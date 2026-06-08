OWA "Additional storage providers" lets users open and attach files from Dropbox, Box, Google Drive, etc. directly inside the web client — a direct data exfiltration path.

**Remediation Action**

```powershell
Get-OwaMailboxPolicy | Set-OwaMailboxPolicy -AdditionalStorageProvidersAvailable $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 6.5.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
