function ConvertTo-CIPPSensitivityLabelDomainToken {
    <#
    .SYNOPSIS
        Replace the source tenant's domains in a captured sensitivity label's encryption rights with %defaultdomain%.
    .DESCRIPTION
        A label that encrypts for "everyone in my organization" records that as a rights definition whose
        identity is the tenant's own domain:

            [{"Identity":"contoso.com","Rights":"VIEW,DOCEDIT,PRINT"}]

        Deployed as-is to another tenant, that grants the rights to the tenant the label was captured from
        rather than to the tenant it lands in. Swapping the domain for the %defaultdomain% replacement token
        at capture time lets Set-CIPPSensitivityLabel resolve it to each target tenant's own default domain.

        Get-Label reports rights both as objects on the flat EncryptionRightsDefinitions property and as a
        JSON string nested inside the (itself JSON-encoded) encrypt LabelAction, so the same identity shows
        up in the serialized template at several levels of quote escaping. The match therefore runs over
        the serialized template and tolerates any number of escaping backslashes around the quotes.

        Only identities that are exactly one of the tenant's domains are replaced. Users and groups
        ('user@contoso.com') do not exist in other tenants under any name and are left untouched.
    .PARAMETER Json
        The serialized label template.
    .PARAMETER Domains
        The domains that belong to the tenant the label was captured from.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Json,
        [string[]] $Domains
    )

    $DomainPattern = @($Domains | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|'
    if (-not $DomainPattern) { return $Json }

    $Pattern = '(?i)(?<=Identity\\*"\s*:\s*\\*")(?:{0})(?=\\*")' -f $DomainPattern
    return [regex]::Replace($Json, $Pattern, '%defaultdomain%')
}
