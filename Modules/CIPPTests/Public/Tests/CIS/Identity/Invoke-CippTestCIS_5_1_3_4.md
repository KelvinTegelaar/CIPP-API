By default every user can create Microsoft 365 groups through the Azure portal, API or PowerShell, and the creator becomes owner. Restricting Microsoft 365 group creation to administrators keeps group creation and the resources they grant (Teams, SharePoint, mailboxes) under centralized governance.

**Remediation Action**

In the Group.Unified directory settings (templateId `62375ab9-6b52-47ed-826b-58e47e0e304b`) set **EnableGroupCreation** to `false`. If the settings object does not exist, use Microsoft Entra admin center > Entra ID > Groups > General > set **Users can create Microsoft 365 groups in Azure portals, API or PowerShell** to **No** (this creates the object with defaults).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.3.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
