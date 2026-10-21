function Get-HuduUiHumanized {
    <#
        .SYNOPSIS
        Turns a camelCase API value into sentence case, for example inGracePeriod or hybridAzureADJoined.

        .DESCRIPTION
        Acronyms such as AD and the product names below keep their capitals; other words are lowercased.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $ProperNouns = 'Android', 'Apple', 'Autopilot', 'Azure', 'Defender', 'Entra', 'Exchange', 'Google', 'Intune', 'Jamf', 'Microsoft', 'Office', 'Windows'
    $Words = @(($Text -creplace '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])', ' ').Trim() -split '\s+')
    $Sentence = @(foreach ($Word in $Words) {
            if ($Word.Length -gt 1 -and $Word -cmatch '^[A-Z0-9]+$') { $Word }
            elseif ($ProperNouns -contains $Word) { $ProperNouns | Where-Object { $_ -eq $Word } }
            else { $Word.ToLower() }
        }) -join ' '
    $Sentence = $Sentence -replace '\bco management\b', 'co-management'
    $Sentence.Substring(0, 1).ToUpper() + $Sentence.Substring(1)
}
