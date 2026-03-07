function Invoke-ExecScheduleOOOVacation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter    = $Request.Body.tenantFilter
        $Users           = @($Request.Body.Users)
        $InternalMessage = $Request.Body.internalMessage
        $ExternalMessage = $Request.Body.externalMessage
        $StartDate       = $Request.Body.startDate
        $EndDate         = $Request.Body.endDate

        # Extract UPNs — Users arrive as autocomplete option objects with addedFields
        $UserUPNs = @($Users | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value })

        if ($UserUPNs.Count -eq 0) { throw 'At least one user is required.' }

        $UserDisplay = ($UserUPNs | Select-Object -First 3) -join ', '
        if ($UserUPNs.Count -gt 3) { $UserDisplay += " (+$($UserUPNs.Count - 3) more)" }

        $SharedParams = [PSCustomObject]@{
            TenantFilter    = $TenantFilter
            Users           = $UserUPNs
            InternalMessage = $InternalMessage
            ExternalMessage = $ExternalMessage
            APIName         = $APIName
        }

        # Add task — enables OOO with messages at start date
        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Name          = "Add OOO Vacation Mode: $UserDisplay"
            Command       = @{ value = 'Set-CIPPVacationOOO'; label = 'Set-CIPPVacationOOO' }
            Parameters    = ($SharedParams | Select-Object *, @{ n = 'Action'; e = { 'Add' } })
            ScheduledTime = [int64]$StartDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }) -hidden $false

        # Remove task — disables OOO at end date (no messages — preserve user's own updates)
        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Name          = "Remove OOO Vacation Mode: $UserDisplay"
            Command       = @{ value = 'Set-CIPPVacationOOO'; label = 'Set-CIPPVacationOOO' }
            Parameters    = [PSCustomObject]@{
                TenantFilter = $TenantFilter
                Users        = $UserUPNs
                Action       = 'Remove'
                APIName      = $APIName
            }
            ScheduledTime = [int64]$EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }) -hidden $false

        $Result     = "Successfully scheduled OOO vacation mode for $UserDisplay."
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result       = "Failed to schedule OOO vacation mode: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode   = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    })
}
