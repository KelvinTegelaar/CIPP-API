function Set-CIPPPerUserMFA {
    <#
    .SYNOPSIS
    Change Per-User MFA State for a User

    .DESCRIPTION
    Change the Per-User MFA State for a user via the /users/{id}/authentication/requirements endpoint

    .PARAMETER TenantFilter
    Tenant where the user resides

    .PARAMETER userId
    One or more User IDs to set the MFA state for (GUID or UserPrincipalName)

    .PARAMETER State
    State to set the user to (enabled, disabled, enforced)

    .PARAMETER executingUser
    User executing the command

    .EXAMPLE
    Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId user@contoso.onmicrosoft.com -State 'disabled' -executingUser 'mspuser@partner.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$userId,
        [ValidateSet('enabled', 'disabled', 'enforced')]
        $State = 'enabled',
        [string]$executingUser = 'CIPP'
    )
    try {
        $int = 0
        $Body = @{
            perUserMFAstate = $State
        }
        $Requests = foreach ($id in $userId) {
            @{
                id        = $int++
                method    = 'PATCH'
                url       = "users/$id/authentication/requirements"
                body      = $Body
                'headers' = @{
                    'Content-Type' = 'application/json'
                }
            }
        }

        $Requests = New-GraphBulkRequest -tenantid $tenantfilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true

        "Successfully set Per user MFA State for $userId"

        $Users = foreach ($id in $userId) {
            @{
                userId     = $id
                Properties = @{
                    perUserMfaState = $State
                }
            }
        }
        Set-CIPPUserSchemaProperties -TenantFilter $TenantFilter -Users $Users
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Successfully set Per user MFA State to $State for $id" -Sev 'Info' -tenant $TenantFilter
    } catch {
        "Failed to set MFA State for $id : $_"
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Failed to set MFA State to $State for $id : $_" -Sev 'Error' -tenant $TenantFilter
    }
}