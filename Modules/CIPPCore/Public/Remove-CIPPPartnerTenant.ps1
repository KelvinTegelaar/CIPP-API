function Remove-CIPPPartnerTenant {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Removes an additional partner tenant and its stored refresh token.
    .DESCRIPTION
    Deletes the PartnerTenants row, the partner-<tenantid> secret, and its env var. The
    primary partner cannot be removed. Exported for ExecRemovePartnerTenant, so it is listed
    in both command blocklists.
    .PARAMETER PartnerTenantId
    The partner tenant id (GUID) to remove.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PartnerTenantId
    )

    if ($PartnerTenantId -eq $env:TenantID) {
        throw 'Cannot remove the primary partner tenant. Use the setup wizard to change the partner tenant instead.'
    }

    if (-not $PSCmdlet.ShouldProcess($PartnerTenantId, 'Remove partner tenant')) {
        return
    }

    $SecretName = "partner-$PartnerTenantId"
    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretName = $SecretName -replace '-', '_'
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($Secret -and $Secret.PSObject.Properties.Name -contains $DevSecretName) {
                $Secret.$DevSecretName = ''
                $null = Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            }
        } else {
            $KeyVaultName = Get-CippKeyVaultName
            $null = Remove-CippKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction Stop
        }
    } catch {
        Write-Warning "Failed to remove the stored refresh token for partner tenant $PartnerTenantId - $($_.Exception.Message)"
    }
    Remove-Item -Path "env:\$SecretName" -ErrorAction SilentlyContinue

    $Table = Get-CippTable -tablename 'PartnerTenants'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Partners' and RowKey eq '$PartnerTenantId'"
    if ($Row) {
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $Row
    }

    Write-LogMessage -API 'Remove-CIPPPartnerTenant' -message "Removed partner tenant $PartnerTenantId" -Sev 'Info'
    return "Removed partner tenant $PartnerTenantId"
}
