BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Remove-CIPPBecReport { param($TenantFilter, $CaseId) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECReport.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECReport' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = 'x' }
            Query   = $null
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecBECReport' {
    BeforeEach {
        Mock Remove-CIPPBecReport { 'Deleted BEC run BEC-1 for contoso.com' }
        Mock Write-LogMessage { }
    }

    It 'Delete removes the run through Remove-CIPPBecReport, logs it and returns the remover''s message as Results' {
        $Response = Invoke-ExecBECReport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1'; Action = 'Delete' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Deleted BEC run BEC-1 for contoso.com'
        Should -Invoke Remove-CIPPBecReport -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $CaseId -eq 'BEC-1' }
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Info' -and $message -eq 'Deleted BEC run BEC-1' -and $tenant -eq 'contoso.com' -and $API -eq 'ExecBECReport' }
    }

    It 'rejects an unknown action as a formatted error, logs it and deletes nothing' {
        $Response = Invoke-ExecBECReport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1'; Action = 'Archive' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be "Failed: Unknown action 'Archive'"
        Should -Invoke Remove-CIPPBecReport -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -eq "BEC run action 'Archive' failed for BEC-1: Unknown action 'Archive'" -and $LogData.NormalizedError -eq "Unknown action 'Archive'" }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Info' }
    }

    It 'treats a missing action as unknown rather than defaulting to Delete' {
        $Response = Invoke-ExecBECReport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be "Failed: Unknown action ''"
        Should -Invoke Remove-CIPPBecReport -Times 0
    }

    It 'fails cleanly without a caseId, before the action is looked at' {
        $Response = Invoke-ExecBECReport -Request (New-Request @{ tenantFilter = 'contoso.com'; Action = 'Archive' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Failed: caseId is required'
        Should -Invoke Remove-CIPPBecReport -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -match 'caseId is required' -and $API -eq 'ExecBECReport' }
    }

    It 'surfaces a delete failure (run not found) as a formatted error with an error log entry and no success entry' {
        Mock Remove-CIPPBecReport { throw 'BEC run BEC-404 was not found for contoso.com' }
        $Response = Invoke-ExecBECReport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-404'; Action = 'Delete' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Failed: BEC run BEC-404 was not found for contoso.com'
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -eq "BEC run action 'Delete' failed for BEC-404: BEC run BEC-404 was not found for contoso.com" -and $LogData.NormalizedError -match 'not found' }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Info' }
    }
}
