# User Self-Service Creation Is Restricted (Groups, Tenants, Apps)

When regular users can freely create Microsoft 365 groups, security groups, app registrations, or new Azure AD tenants without admin oversight, shadow IT proliferates — new resources are created without governance controls applied, and data may be stored or shared in ungoverned containers.

With Microsoft 365 Copilot deployed, this risk compounds: Copilot can surface content from any resource a user has access to, including newly self-created groups and SharePoint sites. Restricting self-service creation ensures that new M365 resources go through a governed provisioning process where appropriate access controls, retention policies, and sensitivity labels can be applied before Copilot interacts with them.

**Remediation action**
- [Restrict who can create Microsoft 365 Groups](https://learn.microsoft.com/en-us/microsoft-365/admin/create-groups/manage-creation-of-groups)
- [Restrict guest access and self-service in Entra ID user settings](https://learn.microsoft.com/en-us/entra/identity/users/users-default-permissions)
- [Restrict app registrations by non-admin users](https://learn.microsoft.com/en-us/entra/identity-platform/howto-restrict-your-app-to-a-set-of-users)
- [Microsoft 365 governance overview](https://learn.microsoft.com/en-us/microsoft-365/solutions/collaboration-governance-overview)

<!--- Results --->
%TestResult%
