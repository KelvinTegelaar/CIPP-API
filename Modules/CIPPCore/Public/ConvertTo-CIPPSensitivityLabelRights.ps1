function ConvertTo-CIPPSensitivityLabelRights {
    <#
    .SYNOPSIS
        Normalize sensitivity label encryption rights into the 'identity:rights' form New-/Set-Label accept.
    .DESCRIPTION
        Get-Label reports encryption rights as {Identity, Rights} pairs - as objects on the flat
        EncryptionRightsDefinitions property, and as a JSON string inside the encrypt LabelAction's
        'rightsdefinitions' setting:

            [{"Identity":"AuthenticatedUsers","Rights":"VIEW,DOCEDIT,PRINT"}]

        New-Label/Set-Label -EncryptionRightsDefinitions is a MultiValuedProperty of 'identity:rights'
        strings ('AuthenticatedUsers:VIEW,DOCEDIT,PRINT'), so the read shape has to be flattened before it
        can be sent back.

        Rights definitions are the portable half of template-based encryption: unlike an RMS template id
        they carry no tenant-scoped identifiers, so they are what lets a captured label rebuild its
        protection in a different tenant. See ConvertTo-CIPPSensitivityLabelParams.
    .PARAMETER RightsDefinitions
        The value to normalize: a JSON string, an array of {Identity, Rights} objects, or values already
        in the flat 'identity:rights' form (which pass through unchanged).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $RightsDefinitions
    )

    if ($null -eq $RightsDefinitions) { return @() }

    # The LabelAction setting arrives as a JSON string; the flat property arrives as objects.
    if ($RightsDefinitions -is [string]) {
        $Trimmed = $RightsDefinitions.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed)) { return @() }

        if ($Trimmed.StartsWith('[') -or $Trimmed.StartsWith('{')) {
            try {
                $RightsDefinitions = $Trimmed | ConvertFrom-Json
            } catch {
                return @()
            }
        } else {
            # Already 'identity:rights', possibly several entries separated by ';'.
            return @($Trimmed -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    $Result = foreach ($Entry in @($RightsDefinitions)) {
        if ($null -eq $Entry) { continue }

        if ($Entry -is [string]) {
            $Flat = $Entry.Trim()
            if ($Flat) { $Flat }
            continue
        }

        $Identity = "$($Entry.Identity)".Trim()
        if (-not $Identity) { continue }

        # Rights are a comma-separated string in the read shape; tolerate an array of individual rights.
        $Rights = if ($Entry.Rights -is [string]) { "$($Entry.Rights)" } else { @($Entry.Rights) -join ',' }
        $Rights = ($Rights -replace '\s*,\s*', ',').Trim(' ', ',')
        if (-not $Rights) { continue }

        '{0}:{1}' -f $Identity, $Rights
    }

    return @($Result | Where-Object { $_ })
}
