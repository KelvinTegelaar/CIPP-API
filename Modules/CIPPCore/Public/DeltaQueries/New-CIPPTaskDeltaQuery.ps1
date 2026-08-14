function New-CIPPTaskDeltaQuery {
    <#
    .SYNOPSIS
        Creates the delta query a DeltaQuery-triggered scheduled task runs against.
    .DESCRIPTION
        Builds the delta query parameters from a task's trigger and hands them to New-GraphDeltaQuery,
        so task creation, the rebuild in Get-DeltaQueryUrl and the offline repair script all key the
        DeltaQueries row identically.
    .PARAMETER Trigger
        The task's Trigger. Accepts the live object from the API and the JSON stored on the task row.
    .PARAMETER TenantFilter
        The tenant to create the delta query for. 'AllTenants' or a tenant group object fans out.
    .PARAMETER PartitionKey
        The RowKey of the scheduled task that owns this delta query.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Trigger,

        [Parameter(Mandatory = $true)]
        $TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$PartitionKey
    )

    if ($Trigger -is [string]) {
        $Trigger = $Trigger | ConvertFrom-Json
    }

    $Resource = $Trigger.DeltaResource.value ?? $Trigger.DeltaResource
    if (!$Resource) {
        throw "Trigger for scheduled task '$PartitionKey' has no DeltaResource; the delta query cannot be built."
    }

    $Parameters = @{}
    if ($Trigger.WatchedAttributes -and ($Trigger.WatchedAttributes | Measure-Object).Count -gt 0) {
        $Parameters.'$select' = ($Trigger.WatchedAttributes | ForEach-Object { $_.value ?? $_ }) -join ','
    }
    if ($Trigger.ResourceFilter) {
        $ResourceFilterValues = $Trigger.ResourceFilter | ForEach-Object { $_.value ?? $_ }
        $Parameters.'$filter' = "id eq '" + ($ResourceFilterValues -join "' or id eq '") + "'"
    }

    return New-GraphDeltaQuery -TenantFilter $TenantFilter -Resource $Resource -Parameters $Parameters -PartitionKey $PartitionKey
}
