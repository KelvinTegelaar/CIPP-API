function Get-CIPPTenantAllowBlockListItems {
    <#
    .SYNOPSIS
        Retrieves Tenant Allow/Block List entries from Exchange Online Protection

    .DESCRIPTION
        Fetches every requested list type in a single batched Exchange request and stamps each
        entry with the list type it came from.

        Get-TenantAllowBlockListItems does not return ListType on the records themselves, so the
        type is passed as the batch correlation id (OperationGuid) and re-stamped here. Without
        it the four responses are indistinguishable once merged.

        Shared by the live ListTenantAllowBlockList path and the reporting DB cache writer so both
        produce identically shaped records.

    .PARAMETER TenantFilter
        The tenant to retrieve entries for

    .PARAMETER ListType
        The list types to gather. Defaults to all four.

    .EXAMPLE
        Get-CIPPTenantAllowBlockListItems -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        Get-CIPPTenantAllowBlockListItems -TenantFilter 'contoso.onmicrosoft.com' -ListType 'Sender', 'Url'

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [ValidateSet('Sender', 'Url', 'FileHash', 'IP')]
        [string[]]$ListType = @('Sender', 'Url', 'FileHash', 'IP')
    )

    $CmdletArray = foreach ($Type in $ListType) {
        @{
            OperationGuid = $Type
            CmdletInput   = @{
                CmdletName = 'Get-TenantAllowBlockListItems'
                Parameters = @{ ListType = $Type }
            }
        }
    }

    foreach ($Entry in @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($CmdletArray))) {
        if ($null -eq $Entry) { continue }
        if ($Entry.error) {
            # A list type this tenant does not support must not cost us the other three.
            Write-LogMessage -API 'TenantAllowBlockList' -tenant $TenantFilter -message "Failed to retrieve $($Entry.OperationGuid) allow/block list entries: $($Entry.error)" -sev Warning
            continue
        }
        # A list type with no entries comes back as a synthetic @{ Success; OperationGuid }
        # record rather than nothing at all - only real entries carry an Identity.
        if (-not $Entry.Identity) { continue }
        $Entry | Add-Member -MemberType NoteProperty -Name ListType -Value $Entry.OperationGuid -Force
        $Entry | Select-Object -ExcludeProperty OperationGuid, *'@data.type'*, *'(DateTime])'*
    }
}
