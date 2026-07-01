E8 ML2 requires patches for the operating system within 2 weeks of release (and 48 hours for known exploited vulnerabilities). Update Rings must therefore not defer quality updates beyond 14 days.

**Remediation Action**

1. Intune > Devices > Update rings > each ring > Settings.
2. **Quality update deferral period (days)** = `0` for production, up to `7` for pilot.
3. Configure a deadline of 2 days for installation/restart.

**Links**
- [Update rings in Intune](https://learn.microsoft.com/en-us/mem/intune/protect/windows-10-update-rings)

<!--- Results --->
%TestResult%
