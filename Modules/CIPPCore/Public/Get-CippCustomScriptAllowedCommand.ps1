function Get-CippCustomScriptAllowedCommand {
    <#
    .SYNOPSIS
        Single source of truth for the custom-test command allowlist.

    .DESCRIPTION
        Used by both Test-CustomScriptSecurity (static pre-check) and
        New-CippSandboxInitialSessionState (the ConstrainedLanguage runspace) so the
        validator and the sandbox can never drift apart.

        Notes:
        - New-Object is intentionally NOT allowed — it is the primary sandbox-escape
          vector and is blocked by ConstrainedLanguage anyway.
        - Data access is limited to Get-CIPPTestData. The lower-level New-CIPPDbRequest /
          Get-CIPPDbItem are not exposed: the sandbox serves pre-fetched, tenant-locked
          cache data only.
    #>
    [CmdletBinding()]
    param()

    @(
        # Data shaping
        'ForEach-Object', 'Where-Object', 'Select-Object', 'Sort-Object', 'Group-Object',
        'Measure-Object', 'Compare-Object', 'Get-Unique', 'Get-Member', 'Select-String',

        # Conversion / utility
        'ConvertTo-Json', 'ConvertFrom-Json', 'Get-Date', 'Get-Random', 'New-TimeSpan',
        'New-Guid', 'Write-Output',

        # CIPP read-only data access (provided as a CLM-safe proxy in the sandbox)
        'Get-CIPPTestData'
    )
}
