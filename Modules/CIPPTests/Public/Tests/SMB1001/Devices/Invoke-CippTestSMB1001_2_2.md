SMB1001 (2.2) — Level 2+ — employees who should not be permitted to install software on their workstations or laptops must not have local user accounts with administrative privileges. The Intune-managed implementation has two parts:

1. The Microsoft Entra device registration policy must deny local admin rights to registering users (so a normal user joining a device does not become its local admin).
2. Windows LAPS must be deployed to manage the local administrator credential — without LAPS the local admin password is either shared, static, or unmanaged.

**Remediation Action**

```powershell
# 1. Device registration policy — deny local admin to registering users
$body = @{
    azureADJoin = @{
        localAdmins = @{
            registeringUsers   = @{ '@odata.type' = '#microsoft.graph.noDeviceRegistrationMembership' }
            enableGlobalAdmins = $false
        }
    }
} | ConvertTo-Json -Depth 10
Invoke-MgGraphRequest -Method PUT -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Body $body

# 2. Deploy Windows LAPS via Intune (Endpoint security > Account protection > Local admin password solution)
```

Use CIPP `standards.intuneDeviceRegLocalAdmins` and `standards.laps`, and deploy a LAPS Intune template via `standards.IntuneTemplate`.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Windows LAPS in Microsoft Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/windows-laps-overview)

<!--- Results --->
%TestResult%
