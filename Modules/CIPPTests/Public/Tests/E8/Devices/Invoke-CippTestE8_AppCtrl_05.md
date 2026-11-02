App-control logs (CodeIntegrity event log, AppLocker event logs) must be centrally collected so blocked-execution events become detection signals.

**Remediation Action**

1. Sentinel > Data connectors > Windows Security Events via AMA — include `Microsoft-Windows-CodeIntegrity/Operational` and `Microsoft-Windows-AppLocker/EXE and DLL`.
2. Or: ingest via Defender for Endpoint Advanced Hunting (`DeviceEvents | where ActionType startswith "AppControlCodeIntegrity"`).

**Links**
- [WDAC event logs](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/operations/event-id-explanations)

<!--- Results --->
%TestResult%
