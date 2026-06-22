function Invoke-CippSandboxScript {
    <#
    .SYNOPSIS
        Executes custom-test script content inside a ConstrainedLanguage sandbox runspace.

    .DESCRIPTION
        Compiles and runs the script in a fresh runspace built from the cached sandbox
        InitialSessionState (ConstrainedLanguage + command allowlist + Get-CIPPTestData
        proxy). The script is compiled via AddScript on the trusted side — never via
        [scriptblock]::Create inside the runspace (which CLM blocks) — so it executes
        constrained.

        Pre-fetched, tenant-locked cache data is injected as $CIPPSandboxData for the proxy.
        Parameters are bound by name; passing a parameter the script does not declare is
        harmless (ignored), matching how the test runner supplies -TenantFilter.

        The sandbox imports no CIPP modules — it only needs the proxy and injected data — so
        runspace creation is cheap. (A runspace pool can be layered on later if profiling
        shows creation is hot; per-call creation keeps it concurrency-safe for now.)

    .PARAMETER ScriptContent
        The validated, text-replaced script to run.

    .PARAMETER SandboxData
        Hashtable of pre-fetched cache data keyed by Type (from Get-CippSandboxData).

    .PARAMETER ScriptParameters
        Named parameters to bind to the script (e.g. TenantFilter and custom params).

    .PARAMETER TimeoutSeconds
        Wall-clock execution limit. A script that exceeds it (e.g. an infinite loop) has its
        pipeline stopped and is reported as a terminating timeout.

    .OUTPUTS
        PSCustomObject with Output, Errors, HadErrors, Terminating, TimedOut.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $false)]
        [hashtable]$SandboxData = @{},

        [Parameter(Mandatory = $false)]
        [hashtable]$ScriptParameters = @{},

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60
    )

    # Cache the (reusable) ISS template for the lifetime of the worker process.
    if (-not $script:CippSandboxInitialSessionState) {
        $script:CippSandboxInitialSessionState = New-CippSandboxInitialSessionState
    }

    $Runspace = [runspacefactory]::CreateRunspace($script:CippSandboxInitialSessionState)
    $Runspace.Open()
    try {
        # Trusted host (FullLanguage) seeds the locked tenant's data for the proxy.
        $Runspace.SessionStateProxy.SetVariable('CIPPSandboxData', $SandboxData)

        $PowerShell = [powershell]::Create()
        $PowerShell.Runspace = $Runspace
        try {
            $null = $PowerShell.AddScript($ScriptContent)
            foreach ($Key in $ScriptParameters.Keys) {
                $null = $PowerShell.AddParameter($Key, $ScriptParameters[$Key])
            }

            # Run asynchronously so a runaway script can be cancelled on timeout.
            $AsyncResult = $PowerShell.BeginInvoke()
            $Completed = $AsyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))

            if (-not $Completed) {
                # Exceeded the wall-clock limit (e.g. infinite loop). Stop the pipeline.
                try { $PowerShell.Stop() } catch {}
                return [PSCustomObject]@{
                    Output      = @()
                    Errors      = @("Script exceeded the ${TimeoutSeconds}s execution limit and was cancelled.")
                    HadErrors   = $true
                    Terminating = $true
                    TimedOut    = $true
                }
            }

            try {
                $Output = $PowerShell.EndInvoke($AsyncResult)
            } catch {
                # Terminating error inside the script.
                return [PSCustomObject]@{
                    Output      = @()
                    Errors      = @($_)
                    HadErrors   = $true
                    Terminating = $true
                    TimedOut    = $false
                }
            }

            return [PSCustomObject]@{
                Output      = $Output
                Errors      = @($PowerShell.Streams.Error)
                HadErrors   = $PowerShell.HadErrors
                Terminating = $false
                TimedOut    = $false
            }
        } finally {
            $PowerShell.Dispose()
        }
    } finally {
        $Runspace.Dispose()
    }
}
