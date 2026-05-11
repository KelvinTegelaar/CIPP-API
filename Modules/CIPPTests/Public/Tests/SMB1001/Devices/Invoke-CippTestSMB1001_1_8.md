SMB1001 (1.8) — Level 5 — important digital data must be encrypted at rest. On Windows the Intune-managed implementation is BitLocker, deployed via Endpoint security > Disk encryption (or via a Settings Catalog policy enabling `device_vendor_msft_bitlocker_requiredeviceencryption`).

**Remediation Action**

1. Intune admin centre > Endpoint security > Disk encryption > Create policy.
2. Choose Windows > BitLocker.
3. Configure recovery key escrow to Entra, encryption method, and startup authentication.
4. Assign to All Devices or a target group.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Encrypt Windows devices with BitLocker in Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/encrypt-devices)

<!--- Results --->
%TestResult%
