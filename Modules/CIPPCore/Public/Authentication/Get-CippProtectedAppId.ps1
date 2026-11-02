function Get-CippProtectedAppId {
    <#
    .SYNOPSIS
    App IDs CIPP itself signs in with (SAM, CIPP-SSO / EasyAuth) that must never be managed as API clients.
    #>
    [CmdletBinding()]
    param()

    # Classic Functions sets the EasyAuth clientId to the first API client, so it is only the SSO app on Craft.
    $EasyAuthAppId = $null
    if ($env:CIPPNG -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
        try { $EasyAuthAppId = ($env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction Stop).identityProviders.azureActiveDirectory.registration.clientId } catch { Write-Information "[ProtectedAppId] Could not parse EasyAuth config: $_" }
    }

    $StoredSSOAppId = $null
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        try {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $StoredSSOAppId = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'").SSOAppId
        } catch { Write-Information "[ProtectedAppId] Could not read stored SSO app id: $_" }
    } else {
        $VaultName = Get-CippKeyVaultName
        if ($VaultName) {
            try { $StoredSSOAppId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { Write-Information "[ProtectedAppId] Could not read stored SSO app id: $_" }
        }
    }

    @($EasyAuthAppId, $StoredSSOAppId, $env:CIPP_SSO_MIGRATION_APPID, $env:ApplicationID).Where({ -not [string]::IsNullOrWhiteSpace($_) })
}
