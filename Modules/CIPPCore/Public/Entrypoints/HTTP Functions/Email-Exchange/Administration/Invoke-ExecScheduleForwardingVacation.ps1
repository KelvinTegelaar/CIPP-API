function Invoke-ExecScheduleForwardingVacation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.tenantFilter
        $Users = @($Request.Body.Users)
        $ForwardOption = $Request.Body.forwardOption
        $ForwardInternal = $Request.Body.ForwardInternal.value ?? $Request.Body.ForwardInternal
        $ForwardExternal = $Request.Body.ForwardExternal
        $KeepCopy = if (-not [string]::IsNullOrWhiteSpace($Request.Body.KeepCopy)) { [System.Convert]::ToBoolean($Request.Body.KeepCopy) } else { $false }
        $StartDate = $Request.Body.startDate
        $EndDate = $Request.Body.endDate

        $UserUPNs = @($Users | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value ?? $_ })

        if ($UserUPNs.Count -eq 0) {
            throw 'At least one user is required.'
        }

        $UserDisplay = ($UserUPNs | Select-Object -First 3) -join ', '
        if ($UserUPNs.Count -gt 3) { $UserDisplay += " (+$($UserUPNs.Count - 3) more)" }

        $SharedParams = [PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Users         = $UserUPNs
            ForwardOption = $ForwardOption
            KeepCopy      = $KeepCopy
            APIName       = $APIName
        }

        switch ($ForwardOption) {
            'internalAddress' {
                if ([string]::IsNullOrWhiteSpace($ForwardInternal)) {
                    throw 'Forwarding target is required for internal forwarding.'
                }
                $SharedParams | Add-Member -NotePropertyName 'ForwardInternal' -NotePropertyValue $ForwardInternal -Force
                $TargetValue = $ForwardInternal
            }
            'ExternalAddress' {
                if ([string]::IsNullOrWhiteSpace($ForwardExternal)) {
                    throw 'Forwarding target is required for external forwarding.'
                }
                $SharedParams | Add-Member -NotePropertyName 'ForwardExternal' -NotePropertyValue $ForwardExternal -Force
                $TargetValue = $ForwardExternal
            }
            default {
                throw "$ForwardOption is not a valid forwarding option."
            }
        }

        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Add Forwarding Vacation Mode: $UserDisplay -> $TargetValue"
                Command       = @{ value = 'Set-CIPPVacationForwarding'; label = 'Set-CIPPVacationForwarding' }
                Parameters    = ($SharedParams | Select-Object *, @{ n = 'Action'; e = { 'Add' } })
                ScheduledTime = [int64]$StartDate
                PostExecution = $Request.Body.postExecution
                Reference     = $Request.Body.reference
            }) -hidden $false

        Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Remove Forwarding Vacation Mode: $UserDisplay"
                Command       = @{ value = 'Set-CIPPVacationForwarding'; label = 'Set-CIPPVacationForwarding' }
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

        $Result = "Successfully scheduled forwarding vacation mode for $UserDisplay."
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to schedule forwarding vacation mode: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
