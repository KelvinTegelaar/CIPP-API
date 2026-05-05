SMB1001 (4.7) — Level 3+ — devices that store sensitive, private, or confidential information must be disposed of securely. The standard requires permanent destruction (shredder or external service) for end-of-life devices, or a non-recoverable format if the device is to be reused, sold, or given away.

This is an operational/process control. The Intune lifecycle (Retire / Wipe / managed device cleanup rules) helps remove corporate data from devices that go missing or are decommissioned, but the physical-destruction or full storage-media format step happens outside Microsoft 365 and must be evidenced to your Dynamic Standard Certifier.

**Remediation Action**

1. Document a device-disposal procedure (who approves, how drives are formatted/destroyed, certificate of destruction).
2. Configure Intune managed device cleanup rules (`deviceInactivityBeforeRetirementInDays`) to auto-retire stale devices — see CIPP `standards.intuneDeviceRetirementDays`.
3. For sold/donated devices, run a cryptographic erase or a full disk wipe before handover.
4. For destroyed devices, retain the destruction certificate.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Retire or wipe devices using Intune](https://learn.microsoft.com/en-us/intune/intune-service/remote-actions/devices-wipe)

<!--- Results --->
%TestResult%
