BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function New-GraphGETRequest { param($uri, $tenantid) }
    function New-GraphPostRequest { param($uri, $type, $tenantid, $body) }
    function Write-LogMessage { param($message, $tenant, $API, $sev, $LogData) }
    function Add-CIPPDelegatedPermission { param($RequiredResourceAccess, $ApplicationId, $Tenantfilter) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $Tenantfilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-ExecAppApprovalTemplate.ps1')
}

Describe 'Push-ExecAppApprovalTemplate application manifest' {
    It 'does not send the app list sign-in activity columns to Graph' {
        $Template = @{
            AppType             = 'ApplicationManifest'
            AppName             = 'Contoso App'
            ApplicationManifest = @{
                displayName                  = 'Contoso App'
                signInAudience               = 'AzureADMyOrg'
                signInActivity               = 'Active'
                lastSignInDateTime           = '2026-11-24T18:55:09.624Z'
                daysSinceLastSignIn          = 1
                lastCredentialSignInDateTime = '2026-11-24T18:55:09.624Z'
                unusedCredentialCount        = 0
                credentialUse                = 'All used in 90 days'
            }
        }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 't1'; JSON = ($Template | ConvertTo-Json -Depth 10) } }
        Mock New-GraphGETRequest { @() }
        Mock New-GraphPostRequest { [pscustomobject]@{ appId = 'a4be0e36-68b4-488f-a2ea-374f4ff009ed' } }
        Mock Write-LogMessage {}

        Push-ExecAppApprovalTemplate -Item @{ Tenant = 'a.com'; templateId = 't1' }

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            if ($uri -notlike '*/applications') { return $false }
            $script:Sent = $body | ConvertFrom-Json
            $true
        }
        @($script:Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('displayName', 'signInAudience')
    }
}
