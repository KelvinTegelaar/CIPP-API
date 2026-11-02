function Merge-CIPPIntuneTemplateIdentity {
    <#
    .SYNOPSIS
        Applies the name and description a template will actually be deployed with onto its payload.
    .DESCRIPTION
        A template stores Displayname and Description as columns alongside RAWJson, not inside it.
        Renaming a template, or editing its description, updates the columns and leaves the payload
        untouched. Set-CIPPIntunePolicy then writes the columns over the payload for every type that
        is not named from its payload, so the tenant ends up with the column values.

        Comparing the stored payload against the tenant therefore reports a difference on exactly
        the fields remediation has already brought into line - and remediation can never resolve it,
        because it keeps writing the value the comparison does not expect. Run the baseline through
        this first so it reflects what deployment sends.
    .PARAMETER Policy
        The parsed policy payload to adjust. Returned with the identity fields applied.
    .PARAMETER TemplateType
        The template Type, e.g. 'Catalog', 'Device', 'deviceCompliancePolicies'.
    .PARAMETER DisplayName
        The template's Displayname column.
    .PARAMETER Description
        The template's Description column.
    .EXAMPLE
        $JSONTemplate = Merge-CIPPIntuneTemplateIdentity -Policy $JSONTemplate -TemplateType $TemplateType -DisplayName $displayname -Description $description
    #>
    [CmdletBinding()]
    param(
        # An empty payload parses to null. Accept it and hand it straight back, so a malformed
        # template surfaces as a comparison failure rather than a parameter binding error.
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Policy,
        [Parameter(Mandatory = $true)]
        [string]$TemplateType,
        [string]$DisplayName,
        [string]$Description
    )

    if ($null -eq $Policy) { return $Policy }

    # Types where Set-CIPPIntunePolicy forces the Displayname and Description columns onto the
    # payload before sending it. Catalog and the update profiles deploy their payload as-is, and
    # Admin's RAWJson holds group policy definition values rather than a policy object, so none of
    # them get touched here.
    $ColumnNamedTypes = @(
        'AppProtection',
        'AppConfiguration',
        'deviceCompliancePolicies',
        'Device',
        'hardwareConfigurations'
    )

    if ($TemplateType -notin $ColumnNamedTypes) {
        return $Policy
    }

    if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        $null = $Policy | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
    }

    # Set unconditionally: deployment always writes the column, so an empty column means the tenant
    # policy ends up with an empty description too.
    $null = $Policy | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force

    return $Policy
}
