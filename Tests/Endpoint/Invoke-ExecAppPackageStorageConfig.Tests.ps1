# Pester tests for Invoke-ExecAppPackageStorageConfig: connect and disconnect app package storage.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Set-ExtensionAPIKey { param($Extension, $APIKey) }
    function Remove-ExtensionAPIKey { param($Extension) }
    function Get-CIPPAppPackageStorage { }
    function New-CIPPAzStorageRequest { [CmdletBinding()] param($Service, $Resource, $Component, $QueryParams, $ConnectionString) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecAppPackageStorageConfig.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Request { param($Body, $Query = @{}) [pscustomobject]@{ Query = $Query; Body = [pscustomobject]$Body; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecAppPackageStorageConfig' } } }
    $script:SavedMemo = [System.Environment]::GetEnvironmentVariable('CIPP_APPPACKAGESTORAGE')
}

AfterAll { [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', $script:SavedMemo) }

Describe 'Invoke-ExecAppPackageStorageConfig' {
    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', $null)
        Mock Set-ExtensionAPIKey { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock New-CIPPAzStorageRequest { }
    }

    It 'refuses a connection string without <Missing>' -ForEach @(
        @{ Missing = 'an account key'; Value = 'DefaultEndpointsProtocol=https;AccountName=mine' }
        @{ Missing = 'an account name'; Value = 'DefaultEndpointsProtocol=https;AccountKey=abc' }
    ) {
        $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request @{ ConnectionString = $Value }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        Should -Invoke Set-ExtensionAPIKey -Times 0 -Exactly
    }

    It 'refuses an account it cannot reach' {
        Mock New-CIPPAzStorageRequest { Write-Error 'Status 403' }

        $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request @{ ConnectionString = 'AccountName=mine;AccountKey=abc' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*could not connect to storage account mine.*'
        Should -Invoke Set-ExtensionAPIKey -Times 0 -Exactly
    }

    It 'stores a reachable account in the key vault, the account name in the table, and switches this process to it' {
        $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request @{ ConnectionString = ' DefaultEndpointsProtocol=https;AccountName=mine;AccountKey=abc ' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        Should -Invoke Set-ExtensionAPIKey -Times 1 -Exactly -ParameterFilter { $Extension -eq 'AppPackageStorage' -and $APIKey -eq 'DefaultEndpointsProtocol=https;AccountName=mine;AccountKey=abc' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AccountName -eq 'mine' }
        [System.Environment]::GetEnvironmentVariable('CIPP_APPPACKAGESTORAGE') | Should -Be 'DefaultEndpointsProtocol=https;AccountName=mine;AccountKey=abc'
    }

    Context 'with an account connected' {
        BeforeEach {
            $script:PackageId = '6f1c2a3b-1111-2222-3333-444455556666'
            Mock Remove-ExtensionAPIKey { }
            Mock Remove-CIPPAzDataTableEntity { }
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'AppPackageStorage'; RowKey = 'Settings'; AccountName = 'mine' } } -ParameterFilter { $Filter -like "*'AppPackageStorage'*" }
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'AppPackage'; RowKey = $script:PackageId; AccountName = 'mine' } } -ParameterFilter { $Filter -like "*'AppPackage'" }
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = $script:TemplateJson } } -ParameterFilter { $Filter -like "*'AppTemplate'*" }
        }

        It 'disconnects back to CIPP storage once no template uses its packages, forgetting the unused ones' {
            $script:TemplateJson = '{"Apps":[]}'

            $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request @{ Remove = $true }) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Remove-ExtensionAPIKey -Times 1 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity)[0].RowKey -eq $script:PackageId }
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'Settings' }
            [System.Environment]::GetEnvironmentVariable('CIPP_APPPACKAGESTORAGE') | Should -Be 'default'
        }

        It 'refuses to <Case> while a template uses a package stored in it' -ForEach @(
            @{ Case = 'disconnect'; Body = @{ Remove = $true } }
            @{ Case = 'switch to another account'; Body = @{ ConnectionString = 'AccountName=other;AccountKey=abc' } }
        ) {
            $script:TemplateJson = '{"Apps":[{"config":"{\"packageId\":\"' + $script:PackageId + '\"}"}]}'

            $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*1 app package(s)*stored in mine*'
            Should -Invoke Remove-ExtensionAPIKey -Times 0 -Exactly
            Should -Invoke Set-ExtensionAPIKey -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'replaces the key of the same account while templates use its packages' {
            $script:TemplateJson = "packageId $($script:PackageId)"

            $Response = Invoke-ExecAppPackageStorageConfig -Request (New-Request @{ ConnectionString = 'AccountName=mine;AccountKey=new' }) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Set-ExtensionAPIKey -Times 1 -Exactly
        }
    }
}
