function New-CippCustomScriptExecution {
    <#
    .SYNOPSIS
        Executes a custom PowerShell script in a restricted environment

    .DESCRIPTION
        Runs user-provided PowerShell scripts inside an isolated ConstrainedLanguage
        sandbox runspace:
        - LanguageMode = ConstrainedLanguage blocks New-Object on arbitrary types and all
          .NET method/reflection access (the real containment boundary).
        - A command allowlist (Get-CippCustomScriptAllowedCommand) hides everything else.
        - Read-only data access via a Get-CIPPTestData proxy that serves only pre-fetched,
          tenant-locked cache data — the script cannot reach storage or other tenants.
        - No file system, network, or write operations.
        - Script output can be produced via pipeline output or explicit return.

    .PARAMETER ScriptGuid
        The GUID of the script to execute from the database

    .PARAMETER TenantFilter
        The tenant to execute the script against

    .PARAMETER Parameters
        Optional hashtable of parameters to pass to the script

    .EXAMPLE
        New-CippCustomScriptExecution -ScriptGuid '12345678-1234-1234-1234-123456789012' -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptGuid,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        $Parameters = @{}
    )

    try {
        # Validate ScriptGuid
        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            throw 'ScriptGuid is required'
        }

        # Get script from database
        $Table = Get-CippTable -tablename 'CustomPowershellScripts'
        $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
        $Scripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $Scripts) {
            throw "Script with GUID '$ScriptGuid' not found"
        }

        # Get latest version
        $Script = $Scripts | Sort-Object -Property Version -Descending | Select-Object -First 1

        # Get script content
        $ScriptContent = $Script.ScriptContent

        Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Executing custom script: $($Script.ScriptName) (Version: $($Script.Version))" -sev Info

        # Convert Parameters to hashtable if it's a PSCustomObject (from JSON)
        if ($Parameters -is [PSCustomObject]) {
            $ParamsHash = @{}
            $Parameters.PSObject.Properties | ForEach-Object {
                $ParamsHash[$_.Name] = $_.Value
            }
            $Parameters = $ParamsHash
        } elseif ($null -eq $Parameters) {
            $Parameters = @{}
        }

        # Replace %variable% placeholders FIRST, then validate the final text. Validating
        # before replacement would let substituted content bypass the check.
        $ScriptContent = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $ScriptContent

        # Fast static pre-check (friendly errors). ConstrainedLanguage is the real boundary.
        Test-CustomScriptSecurity -ScriptContent $ScriptContent

        # Pre-fetch the tenant-locked cache data the script asks for (trusted side), so the
        # sandbox proxy can serve it. The sandbox itself has no storage/tenant access.
        $SandboxData = Get-CippSandboxData -ScriptContent $ScriptContent -TenantFilter $TenantFilter

        # Build script parameters (TenantFilter + custom). TenantFilter is supplied for
        # scripts that declare it; data access is tenant-locked regardless.
        $ScriptParams = @{
            TenantFilter = $TenantFilter
        }
        foreach ($key in $Parameters.Keys) {
            if ($key -ne 'TenantFilter' -and $key -ne 'tenantFilter') {
                $ScriptParams[$key] = $Parameters[$key]
            }
        }

        Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Executing script with parameters: $($ScriptParams.Keys -join ', ')" -sev 'Debug'

        # Execute inside the ConstrainedLanguage sandbox.
        $Execution = Invoke-CippSandboxScript -ScriptContent $ScriptContent -SandboxData $SandboxData -ScriptParameters $ScriptParams

        # Deduplicate errors: a single bad expression in a pipeline (e.g. [pscustomobject]
        # inside ForEach-Object) emits the same error once per item, which is just noise.
        $ErrorText = (@($Execution.Errors | ForEach-Object { $_.ToString() }) | Select-Object -Unique) -join '; '

        $Result = $Execution.Output
        # Treat a null-only result as "no output" — a failed expression (e.g. [type]::new()
        # under CLM) emits a single $null, which must not mask the error as a real result.
        $HasOutput = @($Result | Where-Object { $null -ne $_ }).Count -gt 0

        # Surface failures to the caller (e.g. the Run Test UI) instead of returning null and
        # leaving the error only in the logbook. Terminating errors always fail; non-terminating
        # errors fail only when they left no usable output (the typical CLM-rejection case).
        if ($Execution.Terminating -or ($Execution.HadErrors -and -not $HasOutput)) {
            throw "Custom script execution failed: $ErrorText"
        }
        if ($Execution.HadErrors) {
            Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Custom script produced non-terminating errors: $ErrorText" -sev 'Warning'
        }

        # Convert result to array if it's not already
        if ($null -eq $Result) {
            return @()
        } elseif ($Result -is [System.Collections.IEnumerable] -and $Result -isnot [string]) {
            return @($Result)
        } else {
            return $Result
        }

    } catch {
        Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Failed to execute custom script: $($_.Exception.Message)" -sev 'Error'
        throw
    }
}
