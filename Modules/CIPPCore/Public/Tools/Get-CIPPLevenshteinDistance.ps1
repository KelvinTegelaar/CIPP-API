function Get-CIPPLevenshteinDistance {
    <#
    .SYNOPSIS
        Calculates the Levenshtein distance between two strings.
    .DESCRIPTION
        Returns the minimum number of single-character edits (insertions, deletions,
        substitutions) required to transform the Source string into the Target string.
        Comparisons are case-insensitive by default. Use -CaseSensitive to override.
        Optionally returns a normalized distance score between 0.0 (identical) and 1.0.
    .PARAMETER Source
        The source string.
    .PARAMETER Target
        The target string to compare against.
    .PARAMETER CaseSensitive
        If specified, character comparisons are case-sensitive. By default, comparisons
        are case-insensitive.
    .PARAMETER Normalize
        If specified, returns a normalized distance (distance / max length) as a double
        between 0.0 and 1.0, where 0.0 means identical.
    .EXAMPLE
        Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting'
        # Returns: 3
    .EXAMPLE
        Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting' -Normalize
        # Returns: 0.4285...
    .EXAMPLE
        Get-CIPPLevenshteinDistance -Source 'ABC' -Target 'abc' -CaseSensitive
        # Returns: 3
    .NOTES
        The -CaseSensitive switch pattern (ToLowerInvariant upfront + -ceq in the loop)
        was adapted from Get-LevenshteinDistance by Øyvind Kallstad (2014):
        https://github.com/gravejester/Communary.PASM
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$Source,
        [Parameter(Position = 1)]
        [string]$Target,
        [switch]$CaseSensitive,
        [switch]$Normalize
    )

    # Normalize case upfront so the inner loop can always use -ceq (ordinal compare)
    if (-not $CaseSensitive) {
        $Source = $Source.ToLowerInvariant()
        $Target = $Target.ToLowerInvariant()
    }

    $sourceLen = $Source.Length
    $targetLen = $Target.Length

    # Base cases: transforming to/from an empty string costs one op per character
    if ($sourceLen -eq 0) {
        $distance = $targetLen
    } elseif ($targetLen -eq 0) {
        $distance = $sourceLen
    } else {
        # Classic Wagner-Fischer dynamic programming table.
        # $dp[i][j] = minimum edits to turn Source[0..i-1] into Target[0..j-1].
        #
        # A jagged array (int[][]) is used instead of a 2-D array to avoid
        # PowerShell's comma-operator ambiguity with multidimensional indexing.
        $dp = [int[][]]::new($sourceLen + 1)

        for ($i = 0; $i -le $sourceLen; $i++) {
            $dp[$i] = [int[]]::new($targetLen + 1)
            $dp[$i][0] = $i   # cost to delete all of Source[0..i-1] down to empty
        }
        for ($j = 0; $j -le $targetLen; $j++) {
            $dp[0][$j] = $j   # cost to insert all of Target[0..j-1] from empty
        }

        for ($i = 1; $i -le $sourceLen; $i++) {
            for ($j = 1; $j -le $targetLen; $j++) {
                # 0 if the characters already match; 1 if a substitution is needed
                $substitutionCost = if ($Source[$i - 1] -ceq $Target[$j - 1]) { 0 } else { 1 }

                $dp[$i][$j] = [Math]::Min(
                    [Math]::Min(
                        $dp[$i - 1][$j] + 1,                        # delete from Source
                        $dp[$i][$j - 1] + 1                         # insert into Source
                    ),
                    $dp[$i - 1][$j - 1] + $substitutionCost         # substitute
                )
            }
        }

        $distance = $dp[$sourceLen][$targetLen]
    }

    if ($Normalize) {
        $maxLen = [Math]::Max($sourceLen, $targetLen)
        if ($maxLen -eq 0) { return [double]0 }
        return [double]$distance / $maxLen
    }

    return $distance
}
