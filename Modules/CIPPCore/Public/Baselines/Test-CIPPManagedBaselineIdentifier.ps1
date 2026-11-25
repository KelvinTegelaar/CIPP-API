function Test-CIPPManagedBaselineIdentifier {
    <#
    .SYNOPSIS
        Says what in a piece of text could identify a tenant, or nothing when the text is clean.
    .DESCRIPTION
        Shared by the snapshot redaction and by the check on what a partner types into a custom
        baseline request. Finds an email address, the tenant's own name, domains and id, an ID,
        and an IP address or range. -AnyDomain also finds every other host name: the snapshot
        removes those, while a typed request may name a product the client uses.
    .OUTPUTS
        What was found first, worded for a sentence ('an email address'), or $null.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [string[]]$TenantIdentifiers = @(),
        [switch]$AnyDomain
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    if ($Text -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+') { return 'an email address' }

    foreach ($Identifier in $TenantIdentifiers) {
        if ("$Identifier".Trim().Length -lt 3) { continue }
        $Pattern = '(?<![A-Za-z0-9]){0}(?![A-Za-z0-9])' -f [regex]::Escape("$Identifier".Trim())
        if ([regex]::IsMatch($Text, $Pattern, 'IgnoreCase')) { return "the tenant's own name, domain or ID" }
    }

    if ($Text -match '(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(?![0-9A-Fa-f])') { return 'an ID' }

    $Octet = '(?:25[0-5]|2[0-4]\d|1?\d?\d)'
    if ($Text -match "(?<![\d.])(?:$Octet\.){3}$Octet(?:/\d{1,2})?(?![\d.])") { return 'an IP address' }
    $Group = '[0-9A-Fa-f]{1,4}'
    $IPv6 = "(?:(?:${Group}:){3,7}$Group|(?:${Group}:){1,6}:(?:$Group(?::$Group){0,5})?|::(?:${Group}:){0,6}$Group)"
    if ($Text -match "(?<![\w:.])$IPv6(?:/\d{1,3})?(?![\w:])") { return 'an IP address' }

    if ($AnyDomain -and $Text -match '(?<![\w@.-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}(?![\w.-])') { return 'a domain name' }

    $null
}
