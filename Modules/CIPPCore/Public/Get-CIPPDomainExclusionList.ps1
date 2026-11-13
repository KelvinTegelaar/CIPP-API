function Get-CIPPDomainExclusionList {
    <#
    .SYNOPSIS
        Wildcard patterns for domains the Domain Analyser and the DKIM baseline skip.
    .DESCRIPTION
        Built-in service domains (signature services, Teams SBCs) plus the global list set
        under Settings > DNS. Use with -like.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $BuiltIn = @(
        '*.microsoftonline.com'
        '*.mail.onmicrosoft.com'
        '*.exclaimer.cloud'
        '*.excl.cloud'
        '*.codetwo.online'
        '*.call2teams.com'
        '*.signature365.net'
        '*.myteamsconnect.io'
        '*.teams.dstny.com'
        '*.msteams.8x8.com'
        '*.ucconnect.co.uk'
        '*.teams-sbc.dk'
    )
    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
    $Custom = if ($Config.DomainExclusions) { @(ConvertFrom-Json -InputObject $Config.DomainExclusions) }
    @($BuiltIn) + @($Custom)
}
