# Intune multi-admin approval (MAA), end to end: New-GraphPOSTRequest spots Intune's refusal of an
# unjustified write, New-CIPPIntuneApprovalRequest raises the request app-only, and
# Invoke-CIPPIntuneApprovalRetry completes it app-only with the original body.
#
# The app-only part is the point. A request raised or completed with the GDAP token has no requestor in
# the customer tenant and can never be completed.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, $SkipCache, [switch]$UseCertificate) @{} }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP/test' }
    function Get-NormalizedError { param($Message) $Message }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $Headers, $ContentType, [switch]$SkipHttpErrorCheck, $ResponseHeadersVariable) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPScheduledTask { param($Task, $Hidden) }
    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Set-CIPPAssignedPolicy { param($GroupName, $PolicyId, $PlatformType, $Type, $TenantFilter, $ExcludeGroup, $AssignmentMode) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-CIPPIntuneApprovalRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Invoke-CIPPIntuneApprovalRetry.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Code = 'a1b2c3d4-0000-1111-2222-333344445555'
    $script:CreateUri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
    $script:Body = '{"name":"Test policy"}'

    function New-GraphError([string]$Message) {
        $Exception = [System.Exception]::new($Message)
        $Exception.Data['RawErrorBody'] = $Message
        $Exception
    }
}

Describe 'New-GraphPOSTRequest MAA detection' {
    BeforeEach {
        Mock New-CIPPIntuneApprovalRequest { 'raised' }
    }

    It 'hands the refused write to the approval request with method, body and assignment' {
        Mock Invoke-CIPPRestMethod { throw "Header 'x-msft-approval-justification' is required to request approval" }
        $Assign = @{ GroupName = 'allLicensedUsers' }

        New-GraphPOSTRequest -uri $script:CreateUri -tenantid $script:Tenant -body $script:Body -ApprovalAssignParams $Assign | Should -Be 'raised'
        Should -Invoke New-CIPPIntuneApprovalRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq $script:CreateUri -and $Type -eq 'POST' -and $Body -eq $script:Body -and $AssignParams.GroupName -eq 'allLicensedUsers'
        }
    }

    It 'leaves other errors alone' {
        Mock Invoke-CIPPRestMethod { throw 'Forbidden' }
        { New-GraphPOSTRequest -uri $script:CreateUri -tenantid $script:Tenant -body $script:Body } | Should -Throw 'Forbidden'
        Should -Invoke New-CIPPIntuneApprovalRequest -Times 0 -Exactly
    }

    It 'does not loop when the justification was already sent' {
        Mock Invoke-CIPPRestMethod { throw "Header 'x-msft-approval-justification' is required to request approval" }
        { New-GraphPOSTRequest -uri $script:CreateUri -tenantid $script:Tenant -body $script:Body -AddedHeaders @{ 'x-msft-approval-justification' = 'eA==' } } | Should -Throw
        Should -Invoke New-CIPPIntuneApprovalRequest -Times 0 -Exactly
    }
}

Describe 'New-CIPPIntuneApprovalRequest' {
    BeforeEach {
        Mock Add-CIPPScheduledTask {}
        Mock New-GraphPOSTRequest { throw (New-GraphError "Approval Required. x-msft-approval-code: $script:Code") }
    }

    It 'raises app-only with a base64 justification and the original body' {
        { New-CIPPIntuneApprovalRequest -TenantFilter $script:Tenant -Uri $script:CreateUri -Type 'POST' -Body $script:Body -Justification 'Deploy it' } | Should -Throw '*multi-admin approval*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $AsApp -eq $true -and $body -eq $script:Body -and $type -eq 'POST' -and
            $AddedHeaders['x-msft-approval-justification'] -eq [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Deploy it'))
        }
    }

    It 'schedules one hourly task with the body and assignment, and throws the code' {
        $Thrown = $null
        try {
            New-CIPPIntuneApprovalRequest -TenantFilter $script:Tenant -Uri $script:CreateUri -Type 'post' -Body $script:Body -AssignParams @{ GroupName = 'allLicensedUsers' }
        } catch { $Thrown = $_ }
        $Thrown.Exception.Data['IntuneApprovalCode'] | Should -Be $script:Code
        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
            $Task.Recurrence -eq '1h' -and $Task.Command.value -eq 'Invoke-CIPPIntuneApprovalRetry' -and
            $Task.Parameters.ApprovalCode -eq $script:Code -and $Task.Parameters.ResourcePath -eq 'deviceManagement/configurationPolicies' -and
            $Task.Parameters.Type -eq 'POST' -and $Task.Parameters.Body -eq $script:Body -and
            $Task.Parameters.AssignParams.GroupName -eq 'allLicensedUsers' -and $Task.Parameters.RaisedAt -gt 0
        }
    }

    It 'passes an open-request refusal through untouched' {
        Mock New-GraphPOSTRequest { throw (New-GraphError 'An active Approval Request already exists') }
        { New-CIPPIntuneApprovalRequest -TenantFilter $script:Tenant -Uri $script:CreateUri -Body $script:Body } | Should -Throw '*already exists*'
        Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
    }
}

Describe 'Invoke-CIPPIntuneApprovalRetry' {
    BeforeEach {
        Mock Update-AzDataTableEntity {}
        Mock Set-CIPPAssignedPolicy { 'assigned' }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ id = 'new-policy-id' } }
    }

    It 'completes an approved create app-only with the body, then assigns the new policy' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'approved' } }

        $Result = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath 'deviceManagement/configurationPolicies' -Type 'POST' -Body $script:Body -AssignParams @{ GroupName = 'allLicensedUsers' }

        $Result | Should -BeLike '*completed. Assignment applied.'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $AsApp -eq $true -and $body -eq $script:Body -and $type -eq 'POST' -and $AddedHeaders['x-msft-approval-code'] -eq $script:Code
        }
        Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter {
            $PolicyId -eq 'new-policy-id' -and $PlatformType -eq 'deviceManagement' -and $Type -eq 'configurationPolicies' -and $TenantFilter -eq $script:Tenant
        }
    }

    It 'takes the policy id from the path of an update' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'approved' } }
        Mock New-GraphPOSTRequest { $null }

        $null = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath "deviceManagement/deviceConfigurations('existing-id')" -Type 'PATCH' -Body $script:Body -AssignParams @{ GroupName = 'allLicensedUsers' }
        Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'existing-id' -and $Type -eq 'deviceConfigurations' }
    }

    It 'reports a pending assignment approval without failing the completed write' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'approved' } }
        Mock Set-CIPPAssignedPolicy { throw 'Approval request ffff has been raised' }

        $Result = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath 'deviceManagement/configurationPolicies' -Type 'POST' -Body $script:Body -AssignParams @{ GroupName = 'x' }
        $Result | Should -BeLike '*completed. Assignment not applied yet: Approval request ffff*'
    }

    It 'ends its own recurrence once the write completes' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'approved' } }
        $script:CippScheduledTaskIdStorage = [System.Threading.AsyncLocal[string]]::new()
        $script:CippScheduledTaskIdStorage.Value = 'task-1'
        try {
            $null = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath 'deviceManagement/configurationPolicies' -Type 'POST' -Body $script:Body
        } finally { $script:CippScheduledTaskIdStorage.Value = $null }
        Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'task-1' -and $Entity.Recurrence -eq '0' }
    }

    It 'keeps checking while the request is open' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'needsApproval' } }

        $Result = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath 'deviceManagement/configurationPolicies' -Type 'POST' -Body $script:Body -RaisedAt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $Result | Should -BeLike '*still awaiting approval (needsApproval)*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
    }

    It 'gives up once Intune would have expired the request' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Code; status = 'needsApproval' } }
        $script:CippScheduledTaskIdStorage = [System.Threading.AsyncLocal[string]]::new()
        $script:CippScheduledTaskIdStorage.Value = 'task-1'
        try {
            $Result = Invoke-CIPPIntuneApprovalRetry -TenantFilter $script:Tenant -ApprovalCode $script:Code -ResourcePath 'deviceManagement/configurationPolicies' -Type 'POST' -RaisedAt ([DateTimeOffset]::UtcNow.AddDays(-4).ToUnixTimeSeconds())
        } finally { $script:CippScheduledTaskIdStorage.Value = $null }
        $Result | Should -BeLike '*Giving up*'
        Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.Recurrence -eq '0' }
    }
}
