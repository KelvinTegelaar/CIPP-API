function New-CippSandboxInitialSessionState {
    <#
    .SYNOPSIS
        Builds the ConstrainedLanguage InitialSessionState used to run custom tests.

    .DESCRIPTION
        - LanguageMode = ConstrainedLanguage. This is what actually contains user scripts:
          it blocks New-Object on arbitrary types and all .NET method/reflection access,
          which the previous AST allowlist could not.
        - Command allowlist: only the cmdlets in Get-CippCustomScriptAllowedCommand (and their
          aliases) exist in the session. No providers, external programs or module auto-loading.
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

    $Keep = @($InitialSessionState.Commands | Where-Object {
            ($_ -is [System.Management.Automation.Runspaces.SessionStateCmdletEntry] -and $_.Name -in $Allowed) -or
            ($_ -is [System.Management.Automation.Runspaces.SessionStateAliasEntry] -and $_.Definition -in $Allowed)
        })
    $InitialSessionState.Commands.Clear()
    foreach ($Entry in $Keep) { $InitialSessionState.Commands.Add($Entry) }

    # No providers: no file or Env: access, and native programs cannot start.
    $InitialSessionState.Providers.Clear()
    $InitialSessionState.Variables.Add([System.Management.Automation.Runspaces.SessionStateVariableEntry]::new('PSModuleAutoLoadingPreference', 'None', ''))

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
