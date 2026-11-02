Restricting user consent for OAuth applications stops attackers from luring users (including admins) into authorising malicious third-party apps to read mail or files. The Essential Eight ISM-1883 control limits which online services privileged accounts can authorise.

**Remediation Action**

1. Entra ID > Enterprise applications > Consent and permissions > User consent settings.
2. Set to **Allow user consent for apps from verified publishers, for selected permissions** (low-impact) — or **Do not allow user consent**.
3. Entra ID > User settings > **Users can register applications** = No.

**Links**
- [Configure user consent settings](https://learn.microsoft.com/en-us/azure/active-directory/manage-apps/configure-user-consent)
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)

<!--- Results --->
%TestResult%
