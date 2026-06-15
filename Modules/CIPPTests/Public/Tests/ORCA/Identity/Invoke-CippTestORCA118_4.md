Transport rules (mail flow rules) should not be configured to allow list your organization's own domains and bypass spam filtering. Allowing your own domains through transport rules can be exploited by attackers using spoofing techniques. These rules override important security controls and should never be used for internal domain protection.

**Remediation action**

- [Mail flow rules (transport rules) in Exchange Online](https://learn.microsoft.com/exchange/security-and-compliance/mail-flow-rules/mail-flow-rules)
- [Anti-spoofing protection in EOP](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-phishing-protection-spoofing-about)
- [Recommended settings for EOP and Microsoft Defender for Office 365 security](https://learn.microsoft.com/microsoft-365/security/office-365-security/recommended-settings-for-eop-and-office365)

<!--- Results --->
%TestResult%
