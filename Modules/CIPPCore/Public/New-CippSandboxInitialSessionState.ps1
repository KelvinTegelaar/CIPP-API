function New-CippSandboxInitialSessionState {
    <#
    .SYNOPSIS
        Builds the ConstrainedLanguage InitialSessionState used to run custom tests.

    .DESCRIPTION
        - LanguageMode = ConstrainedLanguage. This is what actually contains user scripts:
          it blocks New-Object on arbitrary types and all .NET method/reflection access,
          which the previous AST allowlist could not.
        - Command allowlist: every command from CreateDefault() that is NOT in
          Get-CippCustomScriptAllowedCommand is set Private (invisible to the user script).
        - Get-CIPPTestData is added as a CLM-safe proxy that serves only the host-injected,
          tenant-locked cache data ($CIPPSandboxData). It is Constant so a test cannot shadow
          it to feed bogus data to a later test in the same suite.

        The ISS is a reusable template; callers create a fresh runspace from it per execution.
    #>
    [CmdletBinding()]
    param()

    $Allowed = Get-CippCustomScriptAllowedCommand

    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $InitialSessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage

    foreach ($Entry in @($InitialSessionState.Commands)) {
        if ($Entry.Name -notin $Allowed) {
            $Entry.Visibility = [System.Management.Automation.SessionStateEntryVisibility]::Private
        }
    }

    # CLM-safe data proxy. No script-level .NET — indexes the injected hashtable only.
    $ProxyBody = @'
param([string]$TenantFilter, [string]$Type)
$Key = if ($Type) { $Type } else { '' }
if ($CIPPSandboxData -and $CIPPSandboxData.ContainsKey($Key)) {
    return $CIPPSandboxData[$Key]
}
return @()
'@

    $ProxyEntry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
        'Get-CIPPTestData',
        $ProxyBody,
        [System.Management.Automation.ScopedItemOptions]::Constant,
        $null
    )
    $ProxyEntry.Visibility = [System.Management.Automation.SessionStateEntryVisibility]::Public
    $InitialSessionState.Commands.Add($ProxyEntry)

    return $InitialSessionState
}
