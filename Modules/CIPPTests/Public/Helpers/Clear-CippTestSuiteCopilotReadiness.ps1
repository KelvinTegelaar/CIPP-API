function Clear-CippTestSuiteCopilotReadiness {
    <#
    .SYNOPSIS
        Drops the shared CopilotReadiness users once Invoke-CIPPTestCollection has run the suite.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $script:CippCopilotReadinessUsers = $null
}
