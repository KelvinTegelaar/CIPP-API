function Get-CIPPPartnerRefreshToken {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Returns the SAM refresh token for a partner tenant.
    .DESCRIPTION
    Primary partner: $env:RefreshToken. Additional partners: partner-<tenantid> secret,
    lazily hydrated into an env var (same pattern as direct tenants). Private on purpose -
    returns raw token material.
    .PARAMETER PartnerTenantId
    The partner tenant id (GUID).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PartnerTenantId
    )

    if ($PartnerTenantId -eq $env:TenantID) {
        return $env:RefreshToken
    }

    $SecretName = "partner-$PartnerTenantId"
    $Cached = Get-Item -Path "env:\$SecretName" -ErrorAction SilentlyContinue
    if ($Cached.Value) {
        return $Cached.Value
    }

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-AzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            $DevSecretName = $SecretName -replace '-', '_'
            if ($Secret.$DevSecretName) {
                Set-Item -Path "env:\$SecretName" -Value $Secret.$DevSecretName -Force
            }
        } else {
            $KeyVaultName = Get-CippKeyVaultName
            $Secret = Get-CippKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText -ErrorAction Stop
            if ($Secret) {
                Set-Item -Path "env:\$SecretName" -Value $Secret -Force
            }
        }
    } catch {
        Write-Host "Failed to retrieve refresh token for partner tenant $PartnerTenantId - $($_.Exception.Message)"
    }

    return (Get-Item -Path "env:\$SecretName" -ErrorAction SilentlyContinue).Value
}
