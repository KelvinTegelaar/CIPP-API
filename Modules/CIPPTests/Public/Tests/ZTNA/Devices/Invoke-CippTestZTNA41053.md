Network protection extends Microsoft Defender SmartScreen and Microsoft threat intelligence checks to outbound web traffic from the operating system, including supported browsers and nonbrowser apps. Microsoft documents that it helps prevent connections to malicious or suspicious sites, such as phishing hosts, malicious downloads, scams, and other poor-reputation sources. This matters because threat actors often use a link, script, Office child process, or loader to reach the next payload or command infrastructure after initial access. If network protection is off or only in audit mode, the connection is logged but not blocked, so execution, credential access, lateral movement, and impact can continue. Network protection does not replace user training, DNS controls, or endpoint investigation, and it depends on Defender Antivirus prerequisites. It adds a device-level block for web-based traffic that may bypass browser-only controls. This check uses the pinned MDATP Secure Score control `scid_96` so the test follows the tenant-level Microsoft signal instead of fragile title matching.

**Remediation action**

- [Use network protection](https://learn.microsoft.com/en-us/defender-endpoint/network-protection)
- [Turn on network protection](https://learn.microsoft.com/en-us/defender-endpoint/enable-network-protection)
- [Evaluate network protection](https://learn.microsoft.com/en-us/defender-endpoint/evaluate-network-protection)

<!--- Results --->
%TestResult%
