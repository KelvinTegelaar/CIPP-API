function Test-CIPPCAPolicyPhishingResistant {
    <#
    .SYNOPSIS
        Decides whether a Conditional Access policy enforces a phishing-resistant authentication strength.
    .DESCRIPTION
        A policy counts as phishing-resistant when its authentication strength is the built-in Microsoft
        "Phishing-resistant MFA" strength, when the strength's display name mentions phishing-resistant /
        FIDO2 / Windows Hello / certificate-based, or (the authoritative signal) when the strength resolves
        in the tenant's cached authentication-strength catalog and any allowedCombinations entry contains a
        phishing-resistant method token (fido2, windowsHelloForBusiness, x509 certificate, device-bound
        passkey, hardware OATH).
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

    if ($null -eq $Strength -or [string]::IsNullOrWhiteSpace("$($Strength.id)")) {
        return [bool]($DisplayName -match $PolicyNameRegex)
    }

    if ("$($Strength.id)" -eq $BuiltInId) { return $true }
    if ("$($Strength.displayName)" -match $StrengthNameRegex) { return $true }

    $Resolved = $null
    if ($Context.AuthStrengths -and $Context.AuthStrengths.ContainsKey("$($Strength.id)")) {
        $Resolved = $Context.AuthStrengths["$($Strength.id)"]
    }
    foreach ($Combination in @($Resolved.allowedCombinations)) {
        $Tokens = @("$Combination".ToLowerInvariant() -split '[,\s]+' | Where-Object { $_ })
        foreach ($Token in $Tokens) {
            if ($MethodTokens -contains $Token) { return $true }
        }
    }

    return [bool]($DisplayName -match $PolicyNameRegex)
}
