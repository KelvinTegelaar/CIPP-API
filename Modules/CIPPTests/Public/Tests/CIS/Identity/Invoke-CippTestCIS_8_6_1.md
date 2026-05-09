User-reported messages are the most reliable signal of social engineering campaigns. Enable reporting in Teams and forward to the SOC mailbox.

**Remediation Action**

```powershell
Set-CsTeamsMessagingPolicy -Identity Global -AllowSecurityEndUserReporting $true
Set-ReportSubmissionPolicy -Identity DefaultReportSubmissionPolicy -ReportJunkToCustomizedAddress $true -ReportPhishToCustomizedAddress $true -ReportNotJunkToCustomizedAddress $true -ReportJunkAddresses 'soc@contoso.com' -ReportNotJunkAddresses 'soc@contoso.com' -ReportPhishAddresses 'soc@contoso.com' -ReportChatMessageEnabled $false -ReportChatMessageToCustomizedAddressEnabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.6.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
