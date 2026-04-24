# Users Are on a Qualified Microsoft 365 Apps Update Channel

Microsoft 365 Copilot features in desktop apps (Word, Excel, PowerPoint, Outlook, OneNote) are only delivered to devices on **Current Channel** or **Monthly Enterprise Channel**. Users on Semi-Annual Enterprise Channel or other slower update rings do not receive Copilot feature updates, even if they have a valid Copilot license assigned.

This test uses the Microsoft 365 Copilot Readiness report to check what percentage of users with an M365 Apps desktop license are on a qualified update channel. A threshold of 70% is used — devices on the wrong channel will appear licensed but Copilot features will be silently absent from their desktop apps.

**Remediation action**
- [Change the Microsoft 365 Apps update channel](https://learn.microsoft.com/en-us/deployoffice/updates/change-update-channels)
- [Update channel configuration with Microsoft Intune](https://learn.microsoft.com/en-us/deployoffice/updates/manage-microsoft-365-apps-updates-configuration-manager)
- [Microsoft 365 Apps update channel overview](https://learn.microsoft.com/en-us/deployoffice/updates/overview-update-channels)

<!--- Results --->
%TestResult%
