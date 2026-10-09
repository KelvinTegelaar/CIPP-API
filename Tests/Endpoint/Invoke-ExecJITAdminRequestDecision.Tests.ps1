BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Update-AzDataTableEntity { param($TableName, $Entity) }
    function Get-CIPPAccessRole { param($Request, $Headers) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Send-CIPPJITAdminApprovalNotification { param($ApprovalRequest, $Status, $Note, $Results) }
    function Invoke-ExecJITAdmin { param($Request, $TriggerMetadata) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecJITAdminRequestDecision.ps1' | Select-Object -First 1).FullName

    $RequestId = '11111111-1111-1111-1111-111111111111'

    function New-DecisionRequest {
        param([string]$Caller, [string]$Decision, [string]$Note)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{ userDetails = $Caller } | ConvertTo-Json)))
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecJITAdminRequestDecision' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]@{ tenantFilter = 'contoso.com'; RequestId = $RequestId; Decision = $Decision; Note = $Note }
        }
    }

    function New-Row {
        param([int]$RequiredApprovals = 1, [string]$Decisions = '[]')
        [pscustomobject]@{
            PartitionKey      = 'JITAdminRequest'
            RowKey            = $RequestId
            ETag              = '1'
            State             = 'Pending'
            Tenant            = 'contoso.com'
            TargetUser        = 'jit@contoso.com'
            RequestedBy       = 'tech@msp.com'
            RequesterHeaders  = '{"x-ms-client-principal":"abc"}'
            ApproverRoles     = '["admin","Approvers"]'
            RequiredApprovals = $RequiredApprovals
            Decisions         = $Decisions
            EndDate           = [string][DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeSeconds()
        }
    }
}

Describe 'Invoke-ExecJITAdminRequestDecision' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { New-Row }
        Mock Get-CIPPAccessRole { @('Approvers') }
        Mock Update-AzDataTableEntity { }
        Mock Send-CIPPJITAdminApprovalNotification { }
        Mock Invoke-ExecJITAdmin { [HttpResponseContext]@{ StatusCode = 200; Body = @{ Results = @('Queued') } } }
    }

    It 'does not let the requester approve their own request' {
        Mock Get-CIPPAccessRole { @('admin') }
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'tech@msp.com' -Decision 'Approve') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 403
        $Response.Body.Results[0] | Should -BeLike '*your own request*'
        Should -Invoke Update-AzDataTableEntity -Times 0
    }

    It 'refuses a caller without an approver role' {
        Mock Get-CIPPAccessRole { @('editor') }
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'other@msp.com' -Decision 'Approve') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 403
        Should -Invoke Update-AzDataTableEntity -Times 0
    }

    It 'requires a note to reject' {
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'boss@msp.com' -Decision 'Reject') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Update-AzDataTableEntity -Times 0
    }

    It 'ends the request on a rejection and tells the requester' {
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'boss@msp.com' -Decision 'Reject' -Note 'Not needed') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Update-AzDataTableEntity -Times 1 -ParameterFilter { $Entity.State -eq 'Rejected' -and $Entity.ETag -eq '1' }
        Should -Invoke Send-CIPPJITAdminApprovalNotification -Times 1 -ParameterFilter { $Status -eq 'Rejected' -and $Note -eq 'Not needed' }
        Should -Invoke Invoke-ExecJITAdmin -Times 0
    }

    It 'records an approval without provisioning until enough approvals are in' {
        Mock Get-CIPPAzDataTableEntity { New-Row -RequiredApprovals 2 }
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'boss@msp.com' -Decision 'Approve') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0] | Should -Be 'Approval recorded (1 of 2).'
        Should -Invoke Update-AzDataTableEntity -Times 1 -ParameterFilter { $Entity.State -eq 'Pending' }
        Should -Invoke Invoke-ExecJITAdmin -Times 0
    }

    It 'does not count the same approver twice' {
        Mock Get-CIPPAzDataTableEntity { New-Row -RequiredApprovals 2 -Decisions '[{"By":"boss@msp.com","Decision":"Approve"}]' }
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'boss@msp.com' -Decision 'Approve') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-ExecJITAdmin -Times 0
    }

    It 'provisions as the requester once the last approval is in' {
        Mock Get-CIPPAzDataTableEntity { New-Row -RequiredApprovals 2 -Decisions '[{"By":"boss@msp.com","Decision":"Approve"}]' }
        $Response = Invoke-ExecJITAdminRequestDecision -Request (New-DecisionRequest -Caller 'second@msp.com' -Decision 'Approve') -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Update-AzDataTableEntity -ParameterFilter { $Entity.State -eq 'Approved' -and $Entity.ETag -eq '1' }
        Should -Invoke Invoke-ExecJITAdmin -Times 1 -ParameterFilter {
            $Request.Body.ApprovalRequestId -eq $RequestId -and $Request.Headers.'x-ms-client-principal' -eq 'abc'
        }
        Should -Invoke Send-CIPPJITAdminApprovalNotification -Times 1 -ParameterFilter { $Status -eq 'Approved' }
    }
}
