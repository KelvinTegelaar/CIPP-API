Application control (allowlisting) is the most effective single mitigation against malware. Implement WDAC, Smart App Control, or AppLocker on all Windows endpoints.

**Remediation Action**

1. Intune > Endpoint security > Account protection / Attack surface reduction > **App and browser control** or **Microsoft Defender Application Control (WDAC)**.
2. Deploy a base policy in audit mode, then move to enforced mode.
3. Assign to all Windows devices.

**Links**
- [WDAC overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/)

<!--- Results --->
%TestResult%
