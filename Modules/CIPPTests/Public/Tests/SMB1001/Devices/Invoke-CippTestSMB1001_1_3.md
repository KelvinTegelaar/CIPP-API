SMB1001 (1.3) — Level 1+ — install and enable antivirus on every workstation and laptop. Mobile devices are covered by ensuring built-in protections (Google Play Protect, App Store) are active. The Intune-managed implementation is a Microsoft Defender Antivirus configuration policy under Endpoint security > Antivirus.

**Remediation Action**

1. Intune admin centre > Endpoint security > Antivirus > Create policy.
2. Choose platform (Windows, macOS) and Microsoft Defender Antivirus profile.
3. Configure real-time protection, cloud-delivered protection, automatic sample submission.
4. Assign to All Devices or a target group.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Antivirus policy for Endpoint security in Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/endpoint-security-antivirus-policy)

<!--- Results --->
%TestResult%
