A device compliance policy that sets `osMinimumVersion` causes Conditional Access to block sign-ins from devices on out-of-support builds, providing a strong forcing function for OS patching.

**Remediation Action**

1. Intune > Devices > Compliance policies > Windows 10 / 11 policy.
2. Set **Minimum OS version** to the latest supported build (e.g. `10.0.19045.0` for Windows 10 22H2).
3. Assign to all Windows devices and pair with a CA policy requiring compliant device.

**Links**
- [Windows compliance settings](https://learn.microsoft.com/en-us/mem/intune/protect/compliance-policy-create-windows)

<!--- Results --->
%TestResult%
