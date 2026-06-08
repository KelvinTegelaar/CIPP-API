function Format-CIPPCompliancePolicyParams {
    <#
    .SYNOPSIS
        Build a compliance cmdlet parameter hashtable from a JSON template/policy source.
    .DESCRIPTION
        Used by deploy endpoints and standards for DLP, Retention, Sensitivity Label, and SIT
        compliance cmdlets. Filters the source object via an explicit allowlist of valid
        New-/Set-* cmdlet parameters, drops null/empty/empty-array values, and normalizes
        location-typed fields from complex objects to identity strings (collapsing to 'All'
        when present in the set).

        Allowlist + drop-empty is the canonical approach because Get-* cmdlets in this family
        return many output-only fields that are not valid input.
    .PARAMETER Source
        The source object (typically [PSCustomObject] from ConvertFrom-Json) to clean.
    .PARAMETER AllowedFields
        Names of properties to allow through. Anything else is dropped.
    .PARAMETER LocationFields
        Subset of AllowedFields whose values are location-typed and should be normalized
        from object arrays to identity strings.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] [string[]] $AllowedFields,
        [string[]] $LocationFields = @()
    )

    $clean = @{}
    foreach ($prop in $Source.PSObject.Properties) {
        if ($prop.Name -notin $AllowedFields) { continue }
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
        if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }

        if ($LocationFields -and $prop.Name -in $LocationFields) {
            $items = @($val) | ForEach-Object {
                if ($null -eq $_) { return }
                if ($_ -is [string]) { $_ }
                elseif ($_.Name) { $_.Name }
                elseif ($_.PrimarySmtpAddress) { $_.PrimarySmtpAddress }
                elseif ($_.DisplayName) { $_.DisplayName }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($items.Count -eq 0) { continue }
            $clean[$prop.Name] = if ($items -contains 'All') { 'All' } else { @($items) }
        } else {
            $clean[$prop.Name] = $val
        }
    }
    return $clean
}
