# Tenant Has Sensitivity Labels Configured in Microsoft Purview

Sensitivity labels are a core data governance control that classifies and protects organizational content. Microsoft 365 Copilot is designed to respect sensitivity labels — it will not generate responses that violate label-based protection policies, and it can apply labels to documents it creates or edits. This integration only works when the tenant has labels configured.

Without sensitivity labels, there is no systematic classification of data in the organization, making it harder to control what Copilot can surface and generate. Tenants with a mature labeling framework have a significant governance advantage when deploying Copilot. This test requires a Microsoft Purview or Azure Information Protection license (included in M365 Business Premium, E3, and E5) and will be skipped if the tenant is not licensed.

**Remediation action**
- [Get started with sensitivity labels](https://learn.microsoft.com/en-us/purview/get-started-with-sensitivity-labels)
- [Create and configure sensitivity labels](https://learn.microsoft.com/en-us/purview/create-sensitivity-labels)
- [Apply sensitivity labels to Microsoft 365 Groups](https://learn.microsoft.com/en-us/purview/sensitivity-labels-teams-groups-sites)
- [Copilot and sensitivity labels](https://learn.microsoft.com/en-us/purview/sensitivity-labels-copilot)

<!--- Results --->
%TestResult%
