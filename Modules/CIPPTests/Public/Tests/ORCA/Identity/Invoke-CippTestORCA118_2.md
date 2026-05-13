Transport rules (mail flow rules) should not be configured to allow list entire domains and bypass spam filtering. Transport rules that skip spam filtering for entire domains can be exploited by attackers to deliver malicious content. These rules override anti-spam policies and should only be used in exceptional circumstances with strict conditions.

**Remediation action**

- [Mail flow rules (transport rules) in Exchange Online](https://learn.microsoft.com/exchange/security-and-compliance/mail-flow-rules/mail-flow-rules)
- [Use mail flow rules to inspect message attachments](https://learn.microsoft.com/exchange/security-and-compliance/mail-flow-rules/inspect-message-attachments)
- [Recommended settings for EOP and Microsoft Defender for Office 365 security](https://learn.microsoft.com/microsoft-365/security/office-365-security/recommended-settings-for-eop-and-office365)

<!--- Results --->
%TestResult%
