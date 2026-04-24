function Get-CIPPAlertGlobalAdminNoAltEmail {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        # Get all Global Admin accounts using the role template ID
        $globalAdmins = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members?`$select=id,displayName,userPrincipalName,otherMails" -tenantid $($TenantFilter) -AsApp $true | Where-Object {
            $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' -and $_.'@odata.type' -eq '#microsoft.graph.user'
        }

        # Filter for Global Admins without alternate email addresses
        $adminsWithoutAltEmail = $globalAdmins | Where-Object {
            $null -eq $_.otherMails -or $_.otherMails.Count -eq 0
        }

        if ($adminsWithoutAltEmail.Count -gt 0) {
            $AlertData = foreach ($admin in $adminsWithoutAltEmail) {
                [PSCustomObject]@{
                    DisplayName       = $admin.displayName
                    UserPrincipalName = $admin.userPrincipalName
                    Id                = $admin.id
                    Tenant            = $TenantFilter
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-LogMessage -message "Failed to check alternate email status for Global Admins: $($_.exception.message)" -API 'Global Admin Alt Email Alerts' -tenant $TenantFilter -sev Error
    }
}
