function Resolve-CIPPUserPropertyText {
    <#
    .SYNOPSIS
        Replaces %property% tokens in a text with that user's own Graph properties.
    .DESCRIPTION
        Without -User, returns the Graph property names the text references, so the caller can
        read just those. With -User, returns the text with each token replaced. %FirstName% and
        %LastName% are accepted for givenName and surname, as in the user defaults. A token whose
        property is empty on the user throws, so nobody gets a half-filled value.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,
        $User
    )

    $Aliases = @{ firstname = 'givenName'; lastname = 'surname' }
    $TokenPattern = '%([A-Za-z][A-Za-z0-9_]*)%'
    $PropertyFor = { param($Token) $Aliases[$Token.ToLowerInvariant()] ?? $Token }

    if ($null -eq $User) {
        $Names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Match in [regex]::Matches($Text, $TokenPattern)) {
            [void]$Names.Add((& $PropertyFor $Match.Groups[1].Value))
        }
        return @($Names)
    }

    $Missing = [System.Collections.Generic.List[string]]::new()
    $Result = [regex]::Replace($Text, $TokenPattern, {
            param($Match)
            $Property = & $PropertyFor $Match.Groups[1].Value
            $Value = $User.PSObject.Properties.Where({ $_.Name -eq $Property }, 'First')[0].Value
            $Value = if ($Value -is [array]) { @($Value).Where({ $_ }) -join ', ' } else { "$Value" }
            if ([string]::IsNullOrWhiteSpace($Value)) { $Missing.Add($Match.Value) }
            $Value
        })
    if ($Missing.Count -gt 0) {
        throw "$(@($Missing | Select-Object -Unique) -join ', ') has no value for this user"
    }
    $Result
}
