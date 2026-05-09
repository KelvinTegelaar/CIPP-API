SMB1001 (1.2) — Level 1+ — install and configure a firewall on every device that connects to the Internet. The Intune-managed implementation is the Microsoft Defender Firewall configuration policy under Endpoint security > Firewall. This test passes when at least one firewall policy is assigned to a group.

**Remediation Action**

1. Intune admin centre > Endpoint security > Firewall > Create policy.
2. Choose platform (Windows or macOS) and the Microsoft Defender Firewall profile.
3. Configure rules and assign to All Devices or a target group.

Use CIPP `standards.IntuneTemplate` with a Defender Firewall template to deploy across tenants.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Configure Microsoft Defender Firewall with Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/endpoint-security-firewall-policy)

<!--- Results --->
%TestResult%
