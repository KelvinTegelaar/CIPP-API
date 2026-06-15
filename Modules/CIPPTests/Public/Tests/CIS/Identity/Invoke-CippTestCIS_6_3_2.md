Outlook on the web mailbox policies control whether users can add personal email accounts (`PersonalAccountsEnabled`) and connect personal calendars (`PersonalAccountCalendarsEnabled`) in Outlook. Personal accounts bypass corporate security controls such as anti-malware scanning, DLP, Safe Links, and audit logging. Allowing them alongside the corporate mailbox enables side-channel data exfiltration and creates an ingress path for malware and phishing that bypasses tenant mail-flow protections. Both settings should be `False` on the default OWA mailbox policy.

**Remediation Action**

```powershell
$DefaultPolicy = Get-OwaMailboxPolicy | Where-Object { $_.IsDefault }
Set-OwaMailboxPolicy -Identity $DefaultPolicy.Identity -PersonalAccountsEnabled $false -PersonalAccountCalendarsEnabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 6.3.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
