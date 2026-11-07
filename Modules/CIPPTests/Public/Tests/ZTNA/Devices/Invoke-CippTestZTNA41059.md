EDR in block mode adds Microsoft Defender for Endpoint blocking when Microsoft Defender Antivirus is not the primary antivirus and is running in passive mode. Microsoft documents that it provides added protection from malicious artifacts in this scenario and is available in Defender for Endpoint Plan 2. This matters because threat actors can evade or outpace a third-party antivirus product, then continue from execution into defense evasion, credential access, lateral movement, and impact while defenders investigate. With EDR in block mode disabled, EDR can still detect activity, but malicious artifacts that another antivirus missed might not be actively remediated by Microsoft Defender for Endpoint. The feature does not restore all capabilities that require Defender Antivirus active mode; Microsoft notes that real-time protection, network protection, attack surface reduction rules, and indicators have active-mode dependencies. It is still a critical safety net for tenants that rely on non-Microsoft antivirus. This check uses the pinned MDATP Secure Score control `scid_2004`.

**Remediation action**

- [Endpoint detection and response in block mode](https://learn.microsoft.com/en-us/defender-endpoint/edr-in-block-mode)
- [Frequently asked questions on EDR in block mode](https://learn.microsoft.com/en-us/defender-endpoint/edr-in-block-mode#frequently-asked-questions)
- [Microsoft Defender Antivirus compatibility](https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-compatibility)

<!--- Results --->
%TestResult%
