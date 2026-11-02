function Get-CippBaselineRunContext {
    <#
    .SYNOPSIS
        Returns the baseline run id stored by Set-CippBaselineRunContext for the current invocation.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if ($script:CippBaselineRunIdStorage) { $script:CippBaselineRunIdStorage.Value } else { '' }
}
