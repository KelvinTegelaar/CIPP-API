Disk encryption protects data on lost or stolen devices. The compliance policy must require BitLocker (or `storageRequireEncryption`) so devices that aren't encrypted are blocked by Conditional Access.

**Remediation Action**

1. Intune > Devices > Compliance policies > Windows policy > **Require BitLocker** = Require.
2. Pair with a *BitLocker* configuration profile (Endpoint security > Disk encryption) to actually enable it.
3. Assign to all Windows devices.

**Links**
- [BitLocker policy settings](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)

<!--- Results --->
%TestResult%
