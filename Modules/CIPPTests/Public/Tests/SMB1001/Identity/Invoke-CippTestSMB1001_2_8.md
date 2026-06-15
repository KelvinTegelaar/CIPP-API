SMB1001 (2.8) — Level 4+ — manage remote access cloud credentials with least-privilege IAM. The Microsoft Entra default user role gives standard users the ability to register applications, create new M365 tenants, and create security groups — all administrative actions. SMB1001 2.8.i requires those privileges to be minimised for non-admin accounts.

**Remediation Action**

```powershell
# Disable user-level admin actions in the authorization policy
$body = @{
    defaultUserRolePermissions = @{
        allowedToCreateApps           = $false
        allowedToCreateTenants        = $false
        allowedToCreateSecurityGroups = $false
    }
    allowedToSignUpEmailBasedSubscriptions = $false
} | ConvertTo-Json
Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -Body $body
```

Or use the CIPP standards `standards.DisableAppCreation`, `standards.DisableTenantCreation`, `standards.DisableSecurityGroupUsers`, and `standards.DisableSelfServiceLicenses`.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Restrict default user permissions in Microsoft Entra](https://learn.microsoft.com/en-us/entra/fundamentals/users-default-permissions)

<!--- Results --->
%TestResult%
