Microsoft's vulnerable driver blocklist prevents kernel-level BYOVD attacks. On Windows 11 22H2+ it is auto-enabled with Memory Integrity; older builds require a WDAC driver policy.

**Remediation Action**

1. Intune > Settings catalog > **Memory Integrity / HVCI** = Enabled.
2. Confirm `Enable Microsoft Vulnerable Driver Blocklist` is on.

**Links**
- [Microsoft recommended driver block rules](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/microsoft-recommended-driver-block-rules)

<!--- Results --->
%TestResult%
