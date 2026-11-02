function Set-CIPPSSOStoredCredentials {
    <#
    .SYNOPSIS
        Persists CIPP-SSO credentials to Key Vault (or the DevSecrets table in dev mode).
    .DESCRIPTION
        Writes whichever of -AppId / -AppSecret / -MultiTenant were supplied. Pass only
        the values you actually want to update — e.g. Repair passes only -AppSecret,
        Create passes all three.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$AppId,
        [Parameter(Mandatory = $false)][string]$AppSecret,
        [Parameter(Mandatory = $false)][object]$MultiTenant
    )

    $IsDev = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'

    if ($IsDev) {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
        if (-not $Secret) { $Secret = [PSCustomObject]@{} }
        $Secret | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value 'SSO' -Force
        $Secret | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value 'SSO' -Force
        if ($AppId) { $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppId' -Value $AppId -Force }
        if ($AppSecret) { $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppSecret' -Value $AppSecret -Force }
        if ($PSBoundParameters.ContainsKey('MultiTenant')) {
            $Secret | Add-Member -MemberType NoteProperty -Name 'SSOMultiTenant' -Value ([string]([bool]$MultiTenant)) -Force
        }
        Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
        return
    }

    $VaultName = Get-CippKeyVaultName
    if (-not $VaultName) { throw 'Cannot determine Key Vault name (WEBSITE_SITE_NAME / WEBSITE_DEPLOYMENT_ID not set)' }

    if ($AppId) {
        $ExistingAppIdSecret = $null
        try { $ExistingAppIdSecret = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { }
        if (-not $ExistingAppIdSecret -or $ExistingAppIdSecret -ne $AppId) {
            Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -SecretValue (ConvertTo-SecureString -String $AppId -AsPlainText -Force)
        }
    }

    if ($AppSecret) {
        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppSecret' -SecretValue (ConvertTo-SecureString -String $AppSecret -AsPlainText -Force)
    }

    if ($PSBoundParameters.ContainsKey('MultiTenant')) {
        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOMultiTenant' -SecretValue (ConvertTo-SecureString -String ([string]([bool]$MultiTenant)) -AsPlainText -Force)
    }
}
