A user that suddenly starts sending spam is almost always compromised. Admin notifications surface this immediately.

**Remediation Action**

```powershell
Set-HostedOutboundSpamFilterPolicy -Identity Default -NotifyOutboundSpam $true -NotifyOutboundSpamRecipients 'soc@contoso.com' -BccSuspiciousOutboundMail $true -BccSuspiciousOutboundAdditionalRecipients 'soc@contoso.com'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
