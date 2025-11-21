function Set-CIPPAuditLogUserExclusion {
    <#
    .SYNOPSIS
        Sets user exclusions for Audit Log alerting.
    .DESCRIPTION
        This function allows you to add or remove user exclusions for Audit Log alerting in a specified tenant
        by updating the AuditLogUserExclusions CIPP table.
    .PARAMETER TenantFilter
        The tenant identifier for which to set the user exclusions.
    .PARAMETER Users
        An array of user identifiers (GUIDs or UPNs) to be added or removed from the exclusion list.
    .PARAMETER Action
        The action to perform: 'Add' to add users to the exclusion list, 'Remove' to remove users from the exclusion list.
    .PARAMETER Headers
        The headers to include in the request, typically containing authentication tokens. This is supplied automatically by the API.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$Users,
        [ValidateSet('Add', 'Remove')]
        [string]$Action = 'Add',
        [ValidateSet('Location')]
        [string]$Type = 'Location',
        $Headers
    )

    $AuditLogExclusionsTable = Get-CIPPTable -tablename 'AuditLogUserExclusions'
    $ExistingEntries = Get-CIPPAzDataTableEntity @AuditLogExclusionsTable -Filter "PartitionKey eq '$TenantFilter'"

    $Results = foreach ($User in $Users) {
        if ($Action -eq 'Add') {
            $ExistingUser = $ExistingEntries | Where-Object { $_.RowKey -eq $User -and $_.PartitionKey -eq $TenantFilter -and $_.Type -eq $Type }
            if (!$ExistingUser) {
                $NewEntry = [PSCustomObject]@{
                    PartitionKey = $TenantFilter
                    RowKey       = $User
                    ExcludedOn   = (Get-Date).ToString('o')
                    Type         = $Type
                }
                if ($PSCmdlet.ShouldProcess("Adding exclusion for user: $User")) {
                    Add-CIPPAzDataTableEntity @AuditLogExclusionsTable -Entity $NewEntry
                    "Added audit log exclusion for user: $User"
                    Write-LogMessage -headers $Headers -API 'Set-CIPPAuditLogUserExclusion' -message "Added audit log exclusion for user: $User" -Sev 'Info' -tenant $TenantFilter -LogData $NewEntry
                }
            } else {
                "User $User is already excluded."
            }
        } elseif ($Action -eq 'Remove') {
            if ($ExistingEntries.RowKey -contains $User) {
                if ($PSCmdlet.ShouldProcess("Removing exclusion for user: $User")) {
                    $Entity = $ExistingEntries | Where-Object { $_.RowKey -eq $User -and $_.PartitionKey -eq $TenantFilter -and $_.Type -eq $Type }
                    Remove-AzDataTableEntity @AuditLogExclusionsTable -Entity $Entity
                    Write-LogMessage -headers $Headers -API 'Set-CIPPAuditLogUserExclusion' -message "Removed audit log exclusion for user: $User" -Sev 'Info' -tenant $TenantFilter -LogData $Entity
                    "Removed audit log exclusion for user: $User"
                }
            } else {
                "User $User is not in the exclusion list."
            }
        }
    }
    return @($Results)
}

