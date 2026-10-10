function Resolve-CIPPIPAllowBlockList {
    <#
    .SYNOPSIS
        Finds the CIPP IP allow/block list entry that decides an address.
    .DESCRIPTION
        Of the entries (from Get-CIPPIPAllowBlockList) whose range contains the address, the most
        specific range wins; at equal specificity a tenant entry beats an AllTenants one. So an
        AllTenants block can be relaxed for one tenant by a tenant allow of the same or a narrower
        range, and a single blocked address inside a trusted office range stays blocked.
        Returns the winning entry, or $null when nothing matches.
    .PARAMETER IPAddress
        The address to look up (a port or IPv6 brackets are ignored).
    .PARAMETER Entries
        The list entries.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$IPAddress,
        [AllowNull()][object[]]$Entries
    )

    $Address = ConvertTo-CIPPBecHostAddress -Address $IPAddress
    if (-not $Address -or -not $Entries) { return $null }
    @($Entries | Where-Object { $_ -and (Test-IpInRange -IPAddress $Address -Range $_.Range) } |
            Sort-Object -Property @{ Expression = { [int]$_.Prefix }; Descending = $true }, @{ Expression = { $_.Scope -eq 'Tenant' }; Descending = $true }) |
        Select-Object -First 1
}
