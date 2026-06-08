Microsoft Teams (free) accounts can be created in seconds for phishing — Midnight Blizzard, DarkGate and others use them to deliver payloads. Disable communication with unmanaged Teams.

**Remediation Action**

```powershell
Set-CsExternalAccessPolicy -Identity Global -EnableTeamsConsumerAccess $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
