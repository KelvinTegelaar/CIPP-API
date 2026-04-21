function New-CippCustomScriptExecution {
    <#
    .SYNOPSIS
        Executes a custom PowerShell script in a restricted environment

    .DESCRIPTION
        Runs user-provided PowerShell scripts with strict security constraints:
        - Only data manipulation cmdlets allowed
        - Read-only access to CIPPDB via New-CIPPDbRequest
        - No file system, network, or write operations
        - PowerShell 7.4 syntax supported
        - Script output can be produced via pipeline output or explicit return

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

        # Validate script security constraints using AST parsing
        Test-CustomScriptSecurity -ScriptContent $ScriptContent

        # Create script block with parameter binding
        $ScriptBlock = [scriptblock]::Create($ScriptContent)

        # Build parameter hashtable for splatting (named parameters)
        $ScriptParams = @{
            TenantFilter = $TenantFilter
        }

        # Add custom parameters if any
        foreach ($key in $Parameters.Keys) {
            if ($key -ne 'TenantFilter' -and $key -ne 'tenantFilter') {
                $ScriptParams[$key] = $Parameters[$key]
            }
        }

        Write-LogMessage -API 'CustomScript' -tenant $TenantFilter -message "Executing script with parameters: $($ScriptParams.Keys -join ', ')" -sev 'Debug'

        # Execute the script in current session (already has CIPP functions loaded)
        # The AST validation ensures only safe commands are used
        # Use splatting to pass named parameters
        $Result = & $ScriptBlock @ScriptParams

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
