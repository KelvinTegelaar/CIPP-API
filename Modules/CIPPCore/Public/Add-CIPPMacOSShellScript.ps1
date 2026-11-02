function Add-CIPPMacOSShellScript {
    <#
    .SYNOPSIS
        Creates or updates an Intune macOS shell script by display name. Updates keep the
        script's id and assignments.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string]$Description = '',
        [Parameter(Mandatory = $true)][string]$ScriptContent,
        [string]$FileName,
        [ValidateSet('system', 'user')][string]$RunAsAccount = 'system',
        [string]$ExecutionFrequency,
        [int]$RetryCount = 3,
        [bool]$BlockExecutionNotifications = $true
    )

    $Baseuri = 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts'
    if (-not $FileName) { $FileName = '{0}.sh' -f ($DisplayName -replace '[^a-zA-Z0-9]', '_') }
    $Body = @{
        '@odata.type'               = '#microsoft.graph.deviceShellScript'
        displayName                 = $DisplayName
        description                 = $Description
        fileName                    = $FileName
        runAsAccount                = $RunAsAccount
        retryCount                  = $RetryCount
        blockExecutionNotifications = $BlockExecutionNotifications
        scriptContent               = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-CIPPTextReplacement -Text $ScriptContent -TenantFilter $TenantFilter)))
    }
    if ($ExecutionFrequency) { $Body.executionFrequency = $ExecutionFrequency }

    $Existing = New-GraphGetRequest -uri "$Baseuri`?`$select=id,displayName" -tenantid $TenantFilter | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($Existing) {
        $Body.Remove('@odata.type')
        $null = New-GraphPostRequest -uri "$Baseuri/$($Existing.id)" -tenantid $TenantFilter -type PATCH -body ($Body | ConvertTo-Json -Depth 5)
        return $Existing
    }
    New-GraphPostRequest -uri $Baseuri -tenantid $TenantFilter -type POST -body ($Body | ConvertTo-Json -Depth 5)
}
