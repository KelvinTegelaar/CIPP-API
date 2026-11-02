Office and other internet-facing apps must auto-update so vulnerabilities are remediated within the E8 windows (2 weeks ML1, 48 hours ML2, fully supported only ML3).

**Remediation Action**

1. Office Cloud Policy > **Update Channel** = *Current Channel* or *Monthly Enterprise*; **Enable Automatic Updates** = On.
2. Edge update policies (`UpdateDefault` = 1).
3. Where third-party browsers / PDF viewers are deployed, configure their auto-update.

**Links**
- [Choose Microsoft 365 Apps update channel](https://learn.microsoft.com/en-us/deployoffice/updates/overview-update-channels)

<!--- Results --->
%TestResult%
