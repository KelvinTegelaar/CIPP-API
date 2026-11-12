function Test-CippTemplateWriteAccess {
    <#
    .SYNOPSIS
        Whether the current caller may change or remove a row in the shared templates table.
    .DESCRIPTION
        Templates are global and standards deploy them to every tenant they target, so a caller whose
        role is limited to some tenants may create templates but not change or remove existing ones.
        Calls outside an HTTP request (scheduler, standards) are trusted. Reads the request scope, so it
        must live in CIPPCore.
    .PARAMETER Permission
        Permission the caller must hold for this template type, for endpoints whose own role does not imply it.
    .PARAMETER PartitionKey
        Template partition, used with RowKey for endpoints that create or overwrite by GUID.
    .PARAMETER RowKey
        GUID the request writes to. An empty value or one with no existing row is a new template.
        Omit it for edits and removals of an existing template.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Permission,
        [string]$PartitionKey,
        [AllowNull()][AllowEmptyString()][string]$RowKey
    )

    $CallerPermissions = Get-CippRequestAllowedPermissions
    if ($null -eq $CallerPermissions) { return $true }
    if ($Permission -and $CallerPermissions -notcontains $Permission) { return $false }

    # $null scope means unrestricted; an empty list is a restricted caller entitled to no tenants.
    if (-not $script:CippAllowedTenantsStorage -or $null -eq $script:CippAllowedTenantsStorage.Value) { return $true }

    if ($PSBoundParameters.ContainsKey('RowKey')) {
        if ([string]::IsNullOrWhiteSpace($RowKey)) { return $true }
        $Table = Get-CippTable -tablename 'templates'
        $SafePartition = ConvertTo-CIPPODataFilterValue -Value $PartitionKey -Type String
        $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafePartition' and RowKey eq '$SafeRowKey'" -Property PartitionKey, RowKey
        return -not $Existing
    }
    return $false
}
