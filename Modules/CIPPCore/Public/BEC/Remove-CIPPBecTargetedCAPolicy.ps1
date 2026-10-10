function Remove-CIPPBecTargetedCAPolicy {
    <#
    .SYNOPSIS
        Removes a CIPP BEC containment Conditional Access policy.
    .DESCRIPTION
        Deletes the policy by id, or every CIPP-BEC-managed policy for a user when -UserId is given
        instead. Schedulable (the containment action schedules it at the policy's expiry); a policy
        that is already gone is reported, not failed.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER PolicyId
        The policy id.
    .PARAMETER UserId
        Alternatively, remove every CIPP-BEC policy targeting this user.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$PolicyId,
        [string]$UserId,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    if (-not $PolicyId -and -not $UserId) { throw 'PolicyId or UserId is required' }
    $Ids = @()
    if ($PolicyId) {
        $Ids = @($PolicyId)
    } else {
        $Ids = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,description&$top=999' -tenantid $TenantFilter -AsApp $true | Where-Object { [string]$_.description -like "*ManagedBy=CIPP-BEC;Target=$UserId*" } | ForEach-Object { $_.id })
        if ($Ids.Count -eq 0) {
            $Message = "No CIPP BEC containment policy exists for user $UserId"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
            return $Message
        }
    }
    $Messages = foreach ($Id in $Ids) {
        if (-not $PSCmdlet.ShouldProcess($Id, 'Delete Conditional Access policy')) { continue }
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$Id" -tenantid $TenantFilter -type DELETE -AsApp $true
            $Message = "Removed BEC containment Conditional Access policy $Id"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
            $Message
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            if ($ErrorMessage.NormalizedError -match '(?i)not ?found|404|does not exist') {
                "BEC containment Conditional Access policy $Id was already removed"
            } else {
                $Message = "Failed to remove BEC containment Conditional Access policy $Id`: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                throw $Message
            }
        }
    }
    return ($Messages -join '; ')
}
