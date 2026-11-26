Insurers ask what percentage of endpoints have endpoint protection. This check counts the Intune-managed Windows devices that report Microsoft Defender real-time protection on, and shows the number it is measured against. It also counts devices registered in Entra ID that Intune does not manage, because those are not part of the percentage.

**Remediation Action**

1. Turn on real-time protection on the listed devices with an Intune antivirus policy.
2. Enrol unmanaged devices in Intune, or record how they are protected in the attestation.

<!--- Results --->
%TestResult%
