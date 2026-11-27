BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-GraphPOSTRequest { param($uri, $type, $tenantid, $body, $asApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetMdoAlert.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    . $FunctionPath

    function New-MdoRequest {
        param([hashtable]$Body)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}'))
        $Merged = @{ tenantFilter = 'contoso.com'; GUID = 'alert-1' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSetMdoAlert' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]$Merged
        }
    }
}

Describe 'Invoke-ExecSetMdoAlert assignment' {
    BeforeEach {
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
    }

    It 'leaves the assignee alone on a status change' {
        $Response = Invoke-ExecSetMdoAlert -Request (New-MdoRequest @{ Status = 'resolved' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $Patch = $body | ConvertFrom-Json
            $Patch.status -eq 'resolved' -and $Patch.PSObject.Properties.Name -notcontains 'assignedTo'
        }
    }

    It 'does not assign an unassigned alert when the row value is empty' {
        $null = Invoke-ExecSetMdoAlert -Request (New-MdoRequest @{ Status = 'active'; Assigned = '' }) -TriggerMetadata $null
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { ($body | ConvertFrom-Json).PSObject.Properties.Name -notcontains 'assignedTo' }
    }

    It 'assigns to the caller with AssignToSelf' {
        $null = Invoke-ExecSetMdoAlert -Request (New-MdoRequest @{ AssignToSelf = $true }) -TriggerMetadata $null
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { ($body | ConvertFrom-Json).assignedTo -eq 'tech@msp.com' }
    }

    It 'still assigns an explicit Assigned value' {
        $null = Invoke-ExecSetMdoAlert -Request (New-MdoRequest @{ Assigned = 'other@msp.com' }) -TriggerMetadata $null
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { ($body | ConvertFrom-Json).assignedTo -eq 'other@msp.com' }
    }
}
