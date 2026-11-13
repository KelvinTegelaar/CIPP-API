Safe Links is the Microsoft Defender for Office 365 control that protects users from malicious URLs at the moment of click rather than only at delivery time. Threat actors routinely defeat one-time URL scanning by sending email or Teams messages that contain links to pages that are still benign when the message arrives and are weaponized hours or days later — pointing to credential-harvesting forms, drive-by exploit kits, or convincing fake login pages that capture passwords and session cookies. Safe Links wraps every URL so each click is checked against Microsoft's URL reputation service in real time, regardless of when the message was delivered or where the user clicks it (email, Teams chat, or supported Office desktop and web apps). Without Safe Links, an organization is blind to delayed weaponization across its primary collaboration surfaces, and a single successful credential capture can give threat actors a foothold for lateral phishing, business email compromise, or ransomware staging. Microsoft offers an allow list for known-safe URLs and a no-rewrite mode that preserves the time-of-click reputation check while leaving the original URL intact, so coverage does not require visible URL changes if that is operationally important.

**Remediation action**

- [Safe Links in Microsoft Defender for Office 365](https://learn.microsoft.com/en-us/defender-office-365/safe-links-about?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
- [Configure Safe Links policies](https://learn.microsoft.com/en-us/defender-office-365/safe-links-policies-configure?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
- [Set-SafeLinksPolicy](https://learn.microsoft.com/en-us/powershell/module/exchange/set-safelinkspolicy?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
- [Preset security policies](https://learn.microsoft.com/en-us/defender-office-365/preset-security-policies?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)

<!--- Results --->
%TestResult%
