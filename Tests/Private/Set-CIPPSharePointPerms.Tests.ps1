# Pester tests for Set-CIPPSharePointPerms: one countable { resultText, state } item per user

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPSharePointPerms.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function New-GraphGetRequest { param($uri, $asapp, $tenantid) }
    function New-GraphPostRequest { param($uri, $tenantid, $scope, $type, $body, $AddedHeaders, $ContentType, [switch]$UseCertificate, $AsApp) }
    function Resolve-CIPPSharePointPermissionScope { param($SiteUrl, $TenantFilter) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-CIPPSharePointErrorMessage { param($ErrorMessage) $ErrorMessage }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }

    . $FunctionPath
}

Describe 'Set-CIPPSharePointPerms' {
    BeforeEach {
        Mock Resolve-CIPPSharePointPermissionScope { [pscustomobject]@{ BaseUri = "$SiteUrl/_api"; Scope = 'scope'; Headers = @{} } }
        Mock New-GraphPostRequest {
            if ($uri -like '*/ensureuser') {
                if ($body -like '*bad@contoso.com*') { throw 'User not found' }
                return [pscustomobject]@{ Id = 7 }
            }
        }
    }

    It 'returns a success and an error item when one of two users fails' {
        $Results = @(Set-CIPPSharePointPerms -TenantFilter 'contoso.com' -URL 'https://contoso.sharepoint.com/sites/hr' -OnedriveAccessUser @('good@contoso.com', 'bad@contoso.com'))

        $Results.Count | Should -Be 2
        $Results[0].state | Should -Be 'success'
        $Results[0].resultText | Should -Be 'Successfully added good@contoso.com as a site collection admin of https://contoso.sharepoint.com/sites/hr'
        $Results[1].state | Should -Be 'error'
        $Results[1].resultText | Should -BeLike 'Failed to change access for bad@contoso.com on https://contoso.sharepoint.com/sites/hr - *'
    }

    It 'throws ArgumentException when no user is supplied' {
        { Set-CIPPSharePointPerms -TenantFilter 'contoso.com' -URL 'https://contoso.sharepoint.com/sites/hr' -OnedriveAccessUser @('') } |
            Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'No valid user was supplied to grant or remove OneDrive access for.'
    }

    It 'throws ItemNotFoundException when the user has no OneDrive' {
        Mock New-GraphGetRequest { [pscustomobject]@{ sharepointIds = @{} } }

        { Set-CIPPSharePointPerms -TenantFilter 'contoso.com' -UserId 'user@contoso.com' -OnedriveAccessUser 'admin@contoso.com' } |
            Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage 'Failed to process SharePoint permissions. Error: Could not determine the OneDrive site URL for user@contoso.com*'
    }
}
