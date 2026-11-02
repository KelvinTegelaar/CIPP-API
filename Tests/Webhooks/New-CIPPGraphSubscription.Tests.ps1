BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/New-CIPPGraphSubscription.ps1')

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) @() }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedRow = $Entity }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant) }
    function Get-CIPPHostname { $script:InstanceHostname }
    function New-GraphPostRequest {
        param($uri, $tenantid, $type, $body, [switch]$verbose)
        $script:PostedBody = $body | ConvertFrom-Json
        [pscustomobject]@{ id = 'sub-1'; notificationUrl = $script:PostedBody.notificationUrl }
    }
}

Describe 'New-CIPPGraphSubscription' {
    BeforeEach {
        $script:PostedBody = $null
        $script:SavedRow = $null
    }

    It 'registers against the stored instance URL rather than the host it was handed' {
        $script:InstanceHostname = 'cipp.codin.ch'

        $Result = New-CIPPGraphSubscription -TenantFilter 'z-ag.ch' -TypeofSubscription 'updated' -BaseURL 'gray-stone-07ecdf810.4.azurestaticapps.net' -Resource 'devices' -EventType 'DeviceUpdate' -Recreate

        $Result | Should -BeLike 'Created Webhook subscription for*'
        $script:PostedBody.notificationUrl | Should -BeLike 'https://cipp.codin.ch/api/PublicWebhooks?*'
        $script:SavedRow.WebhookNotificationUrl | Should -BeLike 'https://cipp.codin.ch/*'
    }

    It 'falls back to the host it was handed when no instance URL is known' {
        $script:InstanceHostname = $null

        New-CIPPGraphSubscription -TenantFilter 'z-ag.ch' -TypeofSubscription 'updated' -BaseURL 'cipp.example.com' -Resource 'devices' -EventType 'DeviceUpdate' -Recreate | Out-Null

        $script:PostedBody.notificationUrl | Should -BeLike 'https://cipp.example.com/api/PublicWebhooks?*'
    }
}
