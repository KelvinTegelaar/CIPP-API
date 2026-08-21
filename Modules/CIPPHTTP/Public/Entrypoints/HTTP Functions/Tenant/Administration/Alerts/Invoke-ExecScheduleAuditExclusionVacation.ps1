function Invoke-ExecScheduleAuditExclusionVacation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    .SYNOPSIS
        Schedule a location alert exclusion for a vacation period
    .DESCRIPTION
        Adds the selected users to the audit log location alert exclusion list at the start date and removes them again at the end date, so location-based alerts do not fire while they travel. Works on its own and does not require a Conditional Access policy.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.tenantFilter
        # The users going on vacation
        $Users = @($Request.Body.Users)
        # Unix timestamp for when the exclusion is added
        $StartDate = $Request.Body.startDate
        # Unix timestamp for when the exclusion is removed
        $EndDate = $Request.Body.endDate

        $UserUPNs = @($Users | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value ?? $_ })

        if ($UserUPNs.Count -eq 0) {
            throw 'At least one user is required.'
        }
        if (-not $StartDate -or -not $EndDate) {
            throw 'A start date and end date are required.'
        }

        $UserDisplay = ($UserUPNs | Select-Object -First 3) -join ', '
        if ($UserUPNs.Count -gt 3) { $UserDisplay += " (+$($UserUPNs.Count - 3) more)" }

        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Add Location Alert Exclusion Vacation Mode: $UserDisplay"
                Command       = @{ value = 'Set-CIPPAuditLogUserExclusion'; label = 'Set-CIPPAuditLogUserExclusion' }
                Parameters    = [PSCustomObject]@{
                    TenantFilter = $TenantFilter
                    Users        = $UserUPNs
                    Action       = 'Add'
                    Type         = 'Location'
                }
                ScheduledTime = [int64]$StartDate
                PostExecution = $Request.Body.postExecution
                Reference     = $Request.Body.reference
            }) -hidden $false

        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Remove Location Alert Exclusion Vacation Mode: $UserDisplay"
                Command       = @{ value = 'Set-CIPPAuditLogUserExclusion'; label = 'Set-CIPPAuditLogUserExclusion' }
                Parameters    = [PSCustomObject]@{
                    TenantFilter = $TenantFilter
                    Users        = $UserUPNs
                    Action       = 'Remove'
                    Type         = 'Location'
                }
                ScheduledTime = [int64]$EndDate
                PostExecution = $Request.Body.postExecution
                Reference     = $Request.Body.reference
            }) -hidden $false

        $Result = "Successfully scheduled location alert exclusion vacation mode for $UserDisplay."
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to schedule location alert exclusion vacation mode: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
