function New-CIPPBecCollectorResult {
    <#
    .SYNOPSIS
        Builds the uniform result object every BEC collector returns.
    .DESCRIPTION
        Every collector in the BEC check returns { Data, Complete, Cap, Error, Skipped, Requirement, Count }
        so Push-BECRun can flatten the data into the report and record an honest completeness marker per
        collector. A collector that hit a paging cap reports Complete=$false with the cap it hit; one that
        failed unexpectedly reports Complete=$false with the error text; one that could not run because a
        licence or permission is missing reports Complete=$false, Skipped=$true and the Requirement (e.g.
        'Entra ID P2'). All three keep an empty Data array, so an empty section is never mistaken for a
        clean one - and a skipped check is never mistaken for a passed one.
    .PARAMETER Data
        The collected rows or object. Defaults to an empty array.
    .PARAMETER Complete
        Whether the collector saw everything it asked for. Defaults to $true.
    .PARAMETER Cap
        The cap that was hit (page count, row count) when Complete is $false because of a limit.
    .PARAMETER Error
        Error text when the collector failed.
    .PARAMETER Count
        Number of items in Data; computed when not supplied.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Data = @(),
        [bool]$Complete = $true,
        $Cap = $null,
        # Exposed to callers as -Error; the variable avoids the $Error automatic variable.
        [Alias('Error')][string]$ErrorText = $null,
        # The check could not run because an entitlement is missing (licence or permission), not
        # because it failed - so it is neither complete nor a pass.
        [bool]$Skipped = $false,
        # What the skipped check needs, shown to the analyst (e.g. 'Entra ID P2', 'Defender for Office 365 Plan 2').
        [string]$Requirement = $null,
        $Count = $null
    )

    if ($null -eq $Data) { $Data = @() }
    if ($null -eq $Count) {
        $Count = @($Data).Count
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) { $Complete = $false }
    if ($Skipped) { $Complete = $false }

    return [pscustomobject]@{
        Data        = $Data
        Complete    = [bool]$Complete
        Cap         = $Cap
        Error       = if ([string]::IsNullOrWhiteSpace($ErrorText)) { $null } else { $ErrorText }
        Skipped     = [bool]$Skipped
        Requirement = if ([string]::IsNullOrWhiteSpace($Requirement)) { $null } else { $Requirement }
        Count       = [int]$Count
    }
}
