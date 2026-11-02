# Update-CIPPSAMSecret mints a SAM client secret, stores it, and records its keyId so the token
# timer and the credentials page can tell this instance's secret apart from everyone else's.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPostRequest { param($uri, $type, $Body, $NoAuthCheck, $AsApp) }
    function Update-AppManagementPolicy {}
    function Get-CippKeyVaultName {}
    function Set-CippKeyVaultSecret { param($VaultName, $Name, $SecretValue) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Set-CIPPSAMCredentialRecord { param($KeyId, $Source, $Label, $Headers) }
    function Compare-CIPPSAMCredentialSnapshot { param($Acknowledge, $AcknowledgeNote, $CredentialState) }
    function Set-CIPPCredentialVersion {}
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Update-CIPPSAMSecret.ps1')
}

Describe 'Update-CIPPSAMSecret' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'ApplicationID', 'ApplicationSecret', 'AzureWebJobsStorage', 'NonLocalHostAzurite') { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'old-secret'
        Remove-Item env:AzureWebJobsStorage, env:NonLocalHostAzurite -ErrorAction SilentlyContinue # Key Vault branch

        Mock Update-AppManagementPolicy { [pscustomobject]@{ PolicyAction = 'none' } }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'app-obj-id' } }
        Mock New-GraphPostRequest -ParameterFilter { $uri -match 'addPassword' } { [pscustomobject]@{ secretText = 'new-secret'; keyId = 'new-key-id'; endDateTime = '2028-01-01T00:00:00Z' } }
        Mock New-GraphPostRequest -ParameterFilter { $uri -match 'removePassword' } {}
        Mock Get-CippKeyVaultName { 'kv' }
        Mock Set-CippKeyVaultSecret {}
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'AppCache'; RowKey = 'AppCache'; ApplicationId = 'cached-app-id' } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Set-CIPPSAMCredentialRecord { 'admin@contoso.com' }
        Mock Compare-CIPPSAMCredentialSnapshot {}
        Mock Set-CIPPCredentialVersion { 'v' }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
            else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'stores the secret in Key Vault and records its keyId in AppCache, preserving ApplicationId' {
        $Result = Update-CIPPSAMSecret -Source 'ScheduledRotation'

        $Result.KeyId | Should -Be 'new-key-id'
        $Result.Rotated | Should -BeTrue
        $env:ApplicationSecret | Should -Be 'new-secret'
        Should -Invoke Set-CippKeyVaultSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'ApplicationSecret' -and $VaultName -eq 'kv' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.PartitionKey -eq 'AppCache' -and $Entity.SecretKeyId -eq 'new-key-id' -and $Entity.ApplicationId -eq 'cached-app-id'
        }
        Should -Invoke Set-CIPPCredentialVersion -Times 1 -Exactly
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -match 'removePassword' }
        Should -Invoke Set-CIPPSAMCredentialRecord -Times 1 -Exactly -ParameterFilter { $KeyId -eq 'new-key-id' -and $Source -eq 'ScheduledRotation' }
        Should -Invoke Compare-CIPPSAMCredentialSnapshot -Times 1 -Exactly -ParameterFilter { $Acknowledge -contains 'new-key-id' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Alert' -and $message -like 'Scheduled rotation:*new-key-id*No action needed.' }
    }

    It 'names the acting user on a manual rotation' {
        $null = Update-CIPPSAMSecret -Source 'Manual' -Headers @{ 'x-ms-client-principal' = 'x' }

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Alert' -and $message -like 'Manual rotation by admin@contoso.com:*' }
    }

    It 'rolls the new secret back with removePassword when storing it fails' {
        Mock Set-CippKeyVaultSecret { throw 'vault unavailable' }

        { Update-CIPPSAMSecret } | Should -Throw

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -match 'app-obj-id/removePassword' -and $Body -match 'new-key-id' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Set-CIPPSAMCredentialRecord -Times 0 -Exactly
        $env:ApplicationSecret | Should -Be 'old-secret'
    }
}
