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
        # The read result. A step's %Property% tokens left after rendering resolve against it.
        $Current
    )

    foreach ($Step in @($Remediate.cmdlets)) {
        if (-not $Step) { continue }
        $StepParams = $Step.params ?? [PSCustomObject]@{}
        # Tokens naming a property of the read record (e.g. a policy's localized identity)
        # resolve here; an exact "%prop%" keeps the property's JSON type.
        $StepJson = ConvertTo-Json -Compress -Depth 100 -InputObject $StepParams
        if ($StepJson -match '%[A-Za-z_][A-Za-z0-9_.]*%') {
            $Records = @($Current | Where-Object { $_ })
            if ($Records.Count -ne 1) {
                throw "$($Step.cmdlet) references a read-record token ($($Matches[0])) but the read returned $($Records.Count) records."
            }
            $StepParams = Expand-CIPPBaselineToken -Template $StepParams -Values $Records[0]
            if ((ConvertTo-Json -Compress -Depth 100 -InputObject $StepParams) -match '%[A-Za-z_][A-Za-z0-9_.]*%') {
                throw "$($Step.cmdlet) has an unresolved token ($($Matches[0])) that the read record does not provide."
            }
        }
        $CmdParams = @{}
        foreach ($Property in $StepParams.PSObject.Properties) {
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
        if ($CmdParams.Keys.Count -eq 0 -and @($StepParams.PSObject.Properties).Count -gt 0) { continue }

        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Step.cmdlet -cmdParams $CmdParams -useSystemMailbox $true -Compliance:([bool]($Step.compliance ?? $false))
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $($Step.cmdlet) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}
