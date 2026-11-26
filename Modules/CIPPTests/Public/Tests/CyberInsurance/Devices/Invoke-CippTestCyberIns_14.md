Insurers ask whether sensitive data is encrypted at rest. This check counts the Intune-managed devices that report disk encryption and shows the number it is measured against. It also shows whether a compliance policy requires encryption, how many BitLocker recovery keys are stored in Entra ID, and how many sensitivity labels apply encryption.

**Remediation Action**

1. Deploy a BitLocker (Windows) or FileVault (macOS) policy from Intune.
2. Add an encryption requirement to the device compliance policy.

<!--- Results --->
%TestResult%
