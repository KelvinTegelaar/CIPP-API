BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Entity) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CIPPJITAdminAllowedRoles { param($Headers) [pscustomobject]@{ Restricted = $false; AllowedRoleIds = @() } }
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users'
    . (Join-Path $Folder 'Invoke-EditJITRoleTemplate.ps1')
    . (Join-Path $Folder 'Invoke-RemoveJITRoleTemplate.ps1')

    $TemplateId = '22222222-2222-2222-2222-222222222222'
    function New-TemplateRequest {
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@contoso.com"}'))
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'JITRoleTemplate' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Query   = [pscustomobject]@{ ID = $TemplateId }
            Body    = [pscustomobject]@{ GUID = $TemplateId; templateName = 'Helpdesk'; roles = @([pscustomobject]@{ value = '62e90394-69f5-4237-9190-012177145e10' }) }
        }
    }
}

Describe 'JIT Role Template management' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-AzDataTableEntity { }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'JITRoleTemplate'; RowKey = $TemplateId; JSON = '{"templateName":"Helpdesk","roles":[]}' } }
    }

    It 'refuses edit and delete for a caller restricted by a template' {
        Mock Get-CIPPJITAdminAllowedRoles { [pscustomobject]@{ Restricted = $true; AllowedRoleIds = @() } }
        (Invoke-EditJITRoleTemplate -Request (New-TemplateRequest) -TriggerMetadata $null).StatusCode | Should -Be 403
        (Invoke-RemoveJITRoleTemplate -Request (New-TemplateRequest) -TriggerMetadata $null).StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Remove-AzDataTableEntity -Times 0
    }

    It 'lets an unrestricted caller edit and delete' {
        (Invoke-EditJITRoleTemplate -Request (New-TemplateRequest) -TriggerMetadata $null).StatusCode | Should -Be 200
        (Invoke-RemoveJITRoleTemplate -Request (New-TemplateRequest) -TriggerMetadata $null).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        Should -Invoke Remove-AzDataTableEntity -Times 1
    }
}
