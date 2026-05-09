A custom anti-phishing policy enables impersonation, mailbox intelligence and spoof intelligence protections beyond the defaults.

**Remediation Action**

Use the CIPP `AntiPhishPolicy` standard or:

```powershell
New-AntiPhishPolicy -Name 'Default Anti-Phishing' -Enabled $true -PhishThresholdLevel 2 -EnableMailboxIntelligence $true -EnableMailboxIntelligenceProtection $true -EnableSpoofIntelligence $true -EnableFirstContactSafetyTips $true -EnableSimilarUsersSafetyTips $true -EnableSimilarDomainsSafetyTips $true -EnableUnusualCharactersSafetyTips $true -TargetedUserProtectionAction Quarantine -MailboxIntelligenceProtectionAction Quarantine -TargetedDomainProtectionAction Quarantine -AuthenticationFailAction Quarantine
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.7](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
