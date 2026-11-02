function Set-CIPPCredentialVersion {
    <#
    .SYNOPSIS
        Marks the SAM credentials as changed so every runspace reloads them on its next token call.
    .DESCRIPTION
        Get-GraphToken only reloads credentials when the AppCache ApplicationId differs from its
        runspace environment. A secret rotation, refresh token update or auth-mode change keeps the
        same ApplicationId, so other runspaces would keep stale credentials until they restart.
        Writes a new CredentialVersion to the AppCache row (preserving its other columns), adopts it
        in this runspace so the caller itself does not reload, and drops the shared token cache so
        no worker keeps serving tokens or cached failures minted under the previous credentials.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $ConfigTable = Get-CIPPTable -tablename 'Config'
    $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
    $Version = [guid]::NewGuid().ToString()
    $Entity = @{
        PartitionKey      = 'AppCache'
        RowKey            = 'AppCache'
        ApplicationId     = [string]($AppCache.ApplicationId ?? $env:ApplicationID)
        CredentialVersion = $Version
    }
    if ($null -ne $AppCache.SecretKeyId) { $Entity.SecretKeyId = [string]$AppCache.SecretKeyId }
    $null = Add-CIPPAzDataTableEntity @ConfigTable -Entity $Entity -Force
    $env:CIPPCredentialVersion = $Version
    $null = Clear-CippTokenCache
    return $Version
}
