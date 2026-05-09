SMB1001 (1.9) — Level 5 — implement application control (software allowlisting). Only approved software runs. The Intune-managed implementation is App Control for Business (formerly Windows Defender Application Control / WDAC) or AppLocker, deployed via Endpoint security > Application control or via the Settings Catalog.

**Remediation Action**

1. Intune admin centre > Endpoint security > Application control for Business > Create policy.
2. Choose Audit mode first, validate that legitimate apps are not blocked, then move to Enforce.
3. Define trusted publishers / managed installers.
4. Assign to a test ring then expand to All Devices.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [App Control for Business policies in Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/endpoint-security-app-control-policy)

<!--- Results --->
%TestResult%
