function Test-CIPPCAPolicyPhishingResistant {
    <#
    .SYNOPSIS
        Decides whether a Conditional Access policy enforces a phishing-resistant authentication strength.
    .DESCRIPTION
        A policy counts as phishing-resistant when its authentication strength is the built-in Microsoft
        "Phishing-resistant MFA" strength, or when every allowedCombinations entry of the strength
        consists only of phishing-resistant method tokens (fido2, windowsHelloForBusiness, x509
        certificate, device-bound passkey). Only when the combinations are unknown does it fall back to
        the strength or policy display name mentioning phishing-resistant / FIDO2 / Windows Hello /
        certificate-based.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Reference = $Context.Data.Reference.phishingResistant
    $PolicyNameRegex = if ($Reference.policyNameRegex) { "$($Reference.policyNameRegex)" } else { 'phishing.?resistant' }
    $StrengthNameRegex = if ($Reference.nameRegex) { "$($Reference.nameRegex)" } else { 'phishing.?resistant|fido2|windows hello|certificate.?based' }
    $BuiltInId = if ($Reference.builtInStrengthId) { "$($Reference.builtInStrengthId)" } else { '00000000-0000-0000-0000-000000000004' }
    $MethodTokens = [string[]]@($Reference.methodTokens | ForEach-Object { "$_".ToLowerInvariant() })

    $Strength = $Policy.grantControls.authenticationStrength
    $DisplayName = "$($Policy.displayName)"

    # Without an authentication strength the policy cannot enforce one, whatever it is called
    if ($null -eq $Strength -or [string]::IsNullOrWhiteSpace("$($Strength.id)")) { return $false }

    if ("$($Strength.id)" -eq $BuiltInId) { return $true }

    $Resolved = $null
    if ($Context.AuthStrengths -and $Context.AuthStrengths.ContainsKey("$($Strength.id)")) {
        $Resolved = $Context.AuthStrengths["$($Strength.id)"]
    }
    $Combinations = @($Resolved.allowedCombinations | Where-Object { $_ })
    if ($Combinations.Count -eq 0) { $Combinations = @($Strength.allowedCombinations | Where-Object { $_ }) }

    if ($Combinations.Count -gt 0) {
        # A sign-in may use any allowed combination, so one weaker combination makes the whole
        # strength plain MFA (the built-in "Multifactor authentication" strength allows FIDO2 too).
        foreach ($Combination in $Combinations) {
            $Tokens = @("$Combination".ToLowerInvariant() -split '[,\s]+' | Where-Object { $_ })
            if (@($Tokens | Where-Object { $MethodTokens -notcontains $_ }).Count -gt 0) { return $false }
        }
        return $true
    }

    # Combinations unknown (strength missing from the cached catalog): fall back to the names
    return [bool]("$($Strength.displayName)" -match $StrengthNameRegex -or $DisplayName -match $PolicyNameRegex)
}
