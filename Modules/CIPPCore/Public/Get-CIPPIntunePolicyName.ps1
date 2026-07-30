function Get-CIPPIntunePolicyName {
    <#
    .SYNOPSIS
        Returns the name a template's policy is deployed under in a tenant.
    .DESCRIPTION
        Set-CIPPIntunePolicy names most policy types from the template's Displayname column, forcing
        it onto the payload before sending it to Graph. Catalog and the Windows update profile types
        are the exception - they take their name from the payload itself and ignore the column.

        Anything that has to find a deployed policy again has to use the same rule, otherwise a
        template whose Displayname was edited after it was captured, or whose payload name contains
        a replacement variable, resolves to a name that does not exist in the tenant. The policy is
        then reported as missing while it is sitting right there.
    .PARAMETER TemplateType
        The template Type, e.g. 'Catalog', 'Device', 'deviceCompliancePolicies'.
    .PARAMETER RawJSON
        The policy payload, as a JSON string or an already parsed object. Pass this after text
        replacement has been applied - deployment derives the name from the replaced payload.
    .PARAMETER DisplayName
        The template's Displayname column.
    .EXAMPLE
        Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $RawJSON -DisplayName $Template.Displayname
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateType,
        $RawJSON,
        [string]$DisplayName
    )

    # Types Set-CIPPIntunePolicy names from the payload instead of the Displayname column.
    $PayloadNamedTypes = @(
        'Catalog',
        'windowsDriverUpdateProfiles',
        'windowsFeatureUpdateProfiles',
        'windowsQualityUpdatePolicies',
        'windowsQualityUpdateProfiles'
    )

    if ($TemplateType -notin $PayloadNamedTypes) {
        return $DisplayName
    }

    $Policy = if ($RawJSON -is [string]) {
        try {
            $RawJSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            # Unparseable payload - fall back to the column rather than returning nothing, so the
            # caller still performs a lookup instead of treating the policy as missing outright.
            Write-Warning "Could not read the payload for '$DisplayName' to determine its policy name: $($_.Exception.Message)"
            $null
        }
    } else {
        $RawJSON
    }

    $PayloadName = if ($TemplateType -eq 'Catalog') {
        # Settings Catalog policies use 'name'; Set-CIPPIntunePolicy reads that property directly.
        $Policy.name
    } else {
        $Policy.displayName ?? $Policy.name
    }

    if ([string]::IsNullOrWhiteSpace($PayloadName)) {
        return $DisplayName
    }

    return $PayloadName
}
