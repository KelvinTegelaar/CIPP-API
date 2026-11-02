function Remove-CIPPDirectTenantToken {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Removes the per-tenant refresh token stored for a direct tenant.
    .DESCRIPTION
    Direct tenants authenticate with their own refresh token, kept in Key Vault (or the DevSecrets
    table when running locally) under the tenant id, and cached in an environment variable of the
    same name. This removes both so a tenant that is not a direct tenant cannot fall back to it.
    Cleanup is best effort - failures are logged rather than thrown, because callers use this while
    handling another outcome.
    .PARAMETER TenantId
    The customer id (GUID) of the tenant whose stored credential should be removed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    if (-not $PSCmdlet.ShouldProcess($TenantId, 'Remove direct tenant refresh token')) {
        return
    }

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $SecretName = $TenantId -replace '-', '_'
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($Secret -and $Secret.PSObject.Properties.Name -contains $SecretName) {
                $Secret.$SecretName = ''
                $null = Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            }
            Remove-Item -Path "env:\$SecretName" -ErrorAction SilentlyContinue
        } else {
            $KeyVaultName = Get-CippKeyVaultName
            $null = Remove-CippKeyVaultSecret -VaultName $KeyVaultName -Name $TenantId -ErrorAction Stop
        }

        Remove-Item -Path "env:\$TenantId" -ErrorAction SilentlyContinue
        Write-Information "Removed stored direct tenant refresh token for $TenantId"
    } catch {
        Write-Warning "Failed to remove the stored direct tenant refresh token for $TenantId - $($_.Exception.Message)"
    }
}
