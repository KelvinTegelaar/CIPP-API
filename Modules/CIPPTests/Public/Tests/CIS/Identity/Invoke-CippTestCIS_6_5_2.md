MailTips warn senders before they leak data — large audience, external recipient, restricted recipient, etc. They are a low-cost user-education control.

**Remediation Action**

```powershell
Set-OrganizationConfig -MailTipsAllTipsEnabled $true -MailTipsExternalRecipientsTipsEnabled $true -MailTipsGroupMetricsEnabled $true -MailTipsLargeAudienceThreshold 25
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.5.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
