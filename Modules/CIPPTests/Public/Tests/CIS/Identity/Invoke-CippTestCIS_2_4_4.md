ZAP for Teams retroactively purges malicious chats already delivered to Teams. Without it, malicious links and files persist in conversations even after detection.

**Remediation Action**

```powershell
Set-TeamsProtectionPolicy -Identity 'Teams Protection Policy' -ZapEnabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.4.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
