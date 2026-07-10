ISM-1175 — privileged accounts must be prevented from accessing the internet, email and web services. In a Microsoft 365 tenant the cleanest implementation is to leave privileged accounts unlicensed (no Exchange / Teams / SharePoint mailbox or apps) so that the account cannot send or receive mail, browse SharePoint, or run Office. Entra ID P2 is provisioned via group-based licensing if needed for PIM, but no productivity SKU should be attached.

**Remediation Action**

1. Identify each privileged user listed in the test results.
2. Remove all `Microsoft 365 / Office 365` and `Business Premium` style licenses.
3. Where an admin needs email, use a separate unprivileged mailbox.

**Links**
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)
- [ISM-1175](https://www.cyber.gov.au/ism)

<!--- Results --->
%TestResult%
