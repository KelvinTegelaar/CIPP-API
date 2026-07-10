Microsoft and ACSC both recommend 2-4 dedicated cloud-only Global Administrator break-glass accounts on the `*.onmicrosoft.com` domain that are excluded from MFA-enforcing Conditional Access policies. Their purpose is recovery during a Conditional Access misconfiguration or MFA service outage.

**Remediation Action**

1. Maintain 2 (recommended) or up to 4 cloud-only `*.onmicrosoft.com` GA accounts.
2. Exclude them from MFA-required Conditional Access policies.
3. Protect them with FIDO2 / hardware tokens, store credentials in a sealed envelope, monitor sign-ins via Sentinel.

**Links**
- [Manage emergency access accounts](https://learn.microsoft.com/en-us/azure/active-directory/roles/security-emergency-access)
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)

<!--- Results --->
%TestResult%
