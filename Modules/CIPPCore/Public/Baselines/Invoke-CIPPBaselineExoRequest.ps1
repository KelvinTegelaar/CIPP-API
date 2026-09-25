function Invoke-CIPPBaselineExoRequest {
    <#
    .SYNOPSIS
        ExoRequest executor: runs a definition's ordered cmdlets[] against one tenant.
    .DESCRIPTION
        One script for the whole request type - the ordered array supports remediations that
        need several cmdlets (pre-steps first). Each entry is { cmdlet, params,
        continueOnError, compliance }; continueOnError marks idempotent pre-steps such as
        Enable-OrganizationCustomization, which fails when it already ran. compliance routes
        the step through the Security & Compliance endpoint instead of Exchange Online -
        the *-ProtectionAlert, *-DlpCompliance* and *-Retention* cmdlet families only exist
        there, and calling them without it fails with an unrecognised-cmdlet error. The spec
        arrives fully rendered (%var% + tenant tokens resolved).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here; every executor takes the same arguments.
        $Current
    )

    foreach ($Step in @($Remediate.cmdlets)) {
        if (-not $Step) { continue }
        $CmdParams = @{}
        foreach ($Property in ($Step.params ?? [PSCustomObject]@{}).PSObject.Properties) {
            $CmdParams[$Property.Name] = $Property.Value
        }

        # A GenericHashTable edit (e.g. AllowList Add/Remove) with nothing but empty
        # values still shapes as a real edit and Exchange rejects it with "MultiValuedProperty
        # collections cannot contain null values". Strip empties from Add/Remove, then drop
        # the whole param when nothing real is left.
        foreach ($Key in @($CmdParams.Keys)) {
            $Value = $CmdParams[$Key]
            # Only an object/dictionary can carry an @odata.type edit - null, strings,
            # numbers and bools indexed the same way threw "Cannot index into a null array."
            if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { continue }
            $IsHash = $Value -is [System.Collections.IDictionary]
            $ODataType = if ($IsHash) { $Value['@odata.type'] } else { $Value.PSObject.Properties['@odata.type'].Value }
            if ("$ODataType" -ne '#Exchange.GenericHashTable') { continue }

            $AnyReal = $false
            foreach ($EditKey in @('Add', 'Remove')) {
                $HasEditKey = if ($IsHash) { $Value.Contains($EditKey) } else { $null -ne $Value.PSObject.Properties[$EditKey] }
                if (-not $HasEditKey) { continue }
                $EditValue = if ($IsHash) { $Value[$EditKey] } else { $Value.PSObject.Properties[$EditKey].Value }
                $Cleaned = @($EditValue | Where-Object { $null -ne $_ -and -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_)) })
                if ($Cleaned.Count -gt 0) { $AnyReal = $true }
                if ($IsHash) { $Value[$EditKey] = $Cleaned } else { $Value.$EditKey = $Cleaned }
            }
            if (-not $AnyReal) { $CmdParams.Remove($Key) }
        }
        # .Count would collide with a cmdlet param literally named "Count" (the hashtable
        # returns that key's VALUE, not the entry count) - .Keys.Count is unambiguous.
        if ($CmdParams.Keys.Count -eq 0 -and @(($Step.params ?? [PSCustomObject]@{}).PSObject.Properties).Count -gt 0) { continue }

        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Step.cmdlet -cmdParams $CmdParams -useSystemMailbox $true -Compliance:([bool]($Step.compliance ?? $false))
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $($Step.cmdlet) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}
