Microsoft maintains a Recommended Block Rules list that bans known LOLBin abuse (e.g. `bginfo`, `cdb`, `csi`, `dnx`, `mshta` minus exceptions). Merge this list into your WDAC policy.

**Remediation Action**

1. Download the latest WDAC recommended block rules XML from Microsoft.
2. Merge with your base policy and re-deploy via Intune.

**Links**
- [Microsoft recommended block rules](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/design/applications-that-can-bypass-wdac)

<!--- Results --->
%TestResult%
