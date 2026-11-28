function Complete-CIPPManagedBaselineRequest {
    <#
    .SYNOPSIS
        Saves the baseline CyberDrain delivered for a custom request and marks the request implemented.
    .DESCRIPTION
        Runs when the operator saves a delivered baseline from the editor. Refuses when
        CyberDrain changed the delivery after the editor loaded it, so what is saved is what was
        reviewed. Adds the templates the baseline refers to, saves the baseline as managed,
        records it on the request and tells CyberDrain. A confirm call that fails does not fail
        the save: the hourly check repeats it.
    .OUTPUTS
        What Import-CIPPManagedBaseline returns: @{ GUID; DeltaCount; Templates; Failures }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)]$Baseline,
        [string]$Version,
        $User
    )

    $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $RequestId
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request' and RowKey eq '$SafeId'" |
        Select-CippAllowedTenantData -TenantProperty 'TenantFilter' | Select-Object -First 1
    if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new('That request was not found.') }
    if ("$($Row.Status)" -notin @('Completed - ready to confirm', 'Implemented')) {
        throw [System.ArgumentException]::new("This request is '$($Row.Status)'. Its baseline can be saved once CyberDrain has delivered it.")
    }

    $Package = (Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Query @{ requestId = $RequestId }).package
    if (-not $Package.Baseline) {
        throw [System.ArgumentException]::new('CyberDrain has not delivered a baseline for this request yet.')
    }
    if ($Version -and "$($Package.version)" -ne $Version) {
        throw [System.ArgumentException]::new('CyberDrain updated this baseline while you were reviewing it. Open it again from the Managed tab to see the new version.')
    }

    $Saved = Import-CIPPManagedBaseline -Package $Package -Baseline $Baseline -Kind 'custom' -RequestId $RequestId -User $User

    $Changes = @{
        PartitionKey   = 'request'
        RowKey         = $RequestId
        Status         = 'Implemented'
        BaselineGUID   = "$($Saved.GUID)"
        ConfirmPending = $false
        Error          = ''
    }
    try {
        $null = Invoke-ManagedBaselinesRequest -Path 'PartnerRequestConfirm' -Method POST -Body @{ requestId = $RequestId }
    } catch {
        $Changes.ConfirmPending = $true
        Write-Information "Managed baseline request ${RequestId}: telling CyberDrain it was implemented failed, the hourly check repeats it: $($_.Exception.Message)"
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Changes -OperationType UpsertMerge
    Write-LogMessage -API 'ManagedBaselines' -tenant $Row.TenantFilter -message "Saved the custom managed baseline delivered for $($Row.TenantFilter) ($($Saved.GUID))." -Sev 'Info'

    $Saved
}
