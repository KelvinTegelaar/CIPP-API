BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecJITAdminSettings.ps1' | Select-Object -First 1).FullName
}

Describe 'Invoke-ExecJITAdminSettings Set' {
    It 'saves with no maximum duration over a stored row, which has no MaxDuration column' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'JITAdminSettings'; RowKey = 'JITAdminSettings'; RequireApproval = $true } }
        Mock Add-CIPPAzDataTableEntity { }
        $Request = [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecJITAdminSettings' }
            Headers = @{}
            Body    = [pscustomobject]@{
                Action               = 'Set'
                MaxDuration          = $null
                RequireApproval      = $true
                ApprovalTriggerRoles = @()
                ApproverRoles        = @([pscustomobject]@{ value = 'superadmin' })
                RequiredApprovals    = 2
            }
        }
        $Response = Invoke-ExecJITAdminSettings -Request $Request
        "$($Response.Body.Results)" | Should -Not -BeLike 'Error*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RequiredApprovals -eq 2 -and $null -eq $Entity.MaxDuration }
    }
}
