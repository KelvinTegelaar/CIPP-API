Privileged sign-ins must come from devices the organisation manages. ISM-1380, 1688 and 1689 require admins to operate from a privileged operating environment; in a cloud-first tenant the equivalent is a Conditional Access policy that requires the device to be Intune-compliant or hybrid Azure AD joined before privileged roles are activated.

**Remediation Action**

1. Entra ID > Conditional Access > New policy.
2. Users > Directory roles: include all privileged roles.
3. Cloud apps: All cloud apps.
4. Grant: **Require compliant device** (and/or *Require Hybrid Azure AD joined device*).
5. Enable.

**Links**
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)
- [Require managed devices in CA](https://learn.microsoft.com/en-us/azure/active-directory/conditional-access/require-managed-devices)

<!--- Results --->
%TestResult%
