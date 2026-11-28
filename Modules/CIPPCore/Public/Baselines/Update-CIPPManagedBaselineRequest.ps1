function Update-CIPPManagedBaselineRequest {
    <#
    .SYNOPSIS
        Asks CyberDrain where a custom managed baseline request stands and records the answer.
    .DESCRIPTION
        Shared by Refresh Status and the hourly check. Moves a request from 'Waiting on
        CyberDrain' to 'Completed - ready to confirm' when CyberDrain reports it ready, keeps the
        engineer's notes and the delivered version current, and repeats the confirm call when an
        earlier one failed. A request that was never sent is left alone.
    .OUTPUTS
        The status the request has after the check.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row)

    if (-not $Row.SubmittedAt) { return "$($Row.Status)" }

    $Changes = @{
        PartitionKey = 'request'
        RowKey       = "$($Row.RowKey)"
        LastChecked  = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    }
    if ($Row.ConfirmPending -eq $true) {
        try {
            $null = Invoke-ManagedBaselinesRequest -Path 'PartnerRequestConfirm' -Method POST -Body @{ requestId = "$($Row.RowKey)" }
            $Changes.ConfirmPending = $false
        } catch {
            Write-Information "Managed baseline request $($Row.RowKey): telling CyberDrain it was implemented failed again: $($_.Exception.Message)"
        }
    }

    $Answer = Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Query @{ requestId = "$($Row.RowKey)" }
    $Changes.RemoteStatus = "$($Answer.status)"
    $Changes.RemoteVersion = "$($Answer.version)"
    $Changes.EngineerNotes = "$($Answer.engineerNotes)"

    $Status = "$($Row.Status)"
    if ($Status -eq 'Waiting on CyberDrain') {
        if ("$($Answer.status)" -eq 'ready') {
            $Status = 'Completed - ready to confirm'
            Write-LogMessage -API 'ManagedBaselines' -tenant $Row.TenantFilter -message "The custom managed baseline requested for $($Row.TenantFilter) is ready to confirm." -Sev 'Info'
        } elseif ("$($Answer.status)" -eq 'cancelled') {
            $Status = 'Failed'
            $Changes.Error = 'CyberDrain cancelled this request.'
        }
    }
    $Changes.Status = $Status

    $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
    Add-CIPPAzDataTableEntity @Table -Entity $Changes -OperationType UpsertMerge
    $Status
}
