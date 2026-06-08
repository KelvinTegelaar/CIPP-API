By default any authenticated user can browse the My Groups portal (https://myaccount.microsoft.com/groups) and enumerate group memberships, SharePoint/Teams URLs and group email addresses across the tenant — useful reconnaissance for identifying privileged groups and planning lateral movement. Restricting the web interface limits passive enumeration by users who do not need to browse groups.

**Remediation Action**

Microsoft Entra admin center > Entra ID > Groups > General > Self Service Group Management > set **Restrict user ability to access groups features in My Groups** to **Yes**.

> Manual control — no Graph property is exposed, so CIPP reports this as Informational for manual review.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.3.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
