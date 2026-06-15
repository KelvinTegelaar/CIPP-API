A compromised account that bursts thousands of messages will damage the tenant's outbound reputation. Recipient limits + a BlockUser action contain the blast radius automatically.

**Remediation Action**

```powershell
Set-HostedOutboundSpamFilterPolicy -Identity Default -RecipientLimitExternalPerHour 500 -RecipientLimitInternalPerHour 1000 -RecipientLimitPerDay 1000 -ActionWhenThresholdReached BlockUser
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 2.1.15](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
