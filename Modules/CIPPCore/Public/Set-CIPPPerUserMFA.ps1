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

    .PARAMETER Headers
    User executing the command

    .EXAMPLE
    Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId user@contoso.onmicrosoft.com -State 'disabled' -Headers 'mspuser@partner.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$userId,
        [ValidateSet('enabled', 'disabled', 'enforced')]
        $State = 'enabled',
        $Headers,
        $APIName = 'Set-CIPPPerUserMFA'
    )

    try {
        $UserIds = @($userId)
        $Body = @{ perUserMfaState = $State }
        $Requests = for ($i = 0; $i -lt $UserIds.Count; $i++) {
            @{
                id      = "$i"
                method  = 'PATCH'
                url     = "users/$([uri]::EscapeDataString($UserIds[$i]))/authentication/requirements"
                body    = $Body
                headers = @{ 'Content-Type' = 'application/json' }
            }
        }

        $ById = @{}
        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true)) {
            $ById[[string]$Response.id] = $Response
        }
        $Failures = @(for ($i = 0; $i -lt $UserIds.Count; $i++) {
                $Response = $ById["$i"]
                if ($null -eq $Response) { "$($UserIds[$i]): no response from Graph" }
                elseif ([int]$Response.status -ge 400) { "$($UserIds[$i]): $($Response.body.error.message)" }
            })
        if ($Failures.Count -gt 0) {
            throw "Failed for $($Failures.Count) of $($UserIds.Count) users. $($Failures -join '; ')"
        }

        $Result = "Successfully set Per user MFA State to $State for $($UserIds -join ', ')"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
        $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set MFA State to $State. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
