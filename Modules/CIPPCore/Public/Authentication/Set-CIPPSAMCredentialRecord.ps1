function Set-CIPPSAMCredentialRecord {
    <#
    .SYNOPSIS
        Records provenance (-Source) or an admin "known" label (-Label) for a CIPP-SAM credential.
    .DESCRIPTION
        Upserts Config row PartitionKey 'SAMCredential', RowKey keyId, merging with existing fields.
        The acting user is read from the request headers; without headers it is 'CIPP'.
        Returns the actor name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyId,
        [ValidateSet('ScheduledRotation', 'Manual', 'Setup')]
        [string]$Source,
        [string]$Label,
        $Headers
    )

    $Actor = 'CIPP'
    if ($Headers.'x-ms-client-principal') {
        try { $Actor = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails ?? 'CIPP' } catch { }
    }

    $Table = Get-CIPPTable -tablename 'Config'
    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SAMCredential' and RowKey eq '$KeyId'"
    $Row = @{ PartitionKey = 'SAMCredential'; RowKey = $KeyId }
    foreach ($Name in 'Label', 'FlaggedBy', 'FlaggedAt', 'Source', 'Actor', 'CreatedBy', 'CreatedAt') {
        if ($Existing.$Name) { $Row[$Name] = [string]$Existing.$Name }
    }
    $Now = (Get-Date).ToUniversalTime().ToString('o')
    if ($Source) {
        $Row.Source = $Source
        $Row.Actor = [string]$Actor
        $Row.CreatedBy = [string]($env:WEBSITE_SITE_NAME ?? [System.Environment]::MachineName)
        $Row.CreatedAt = $Now
    }
    if ($Label) {
        $Row.Label = $Label.Substring(0, [Math]::Min(100, $Label.Length))
        $Row.FlaggedBy = [string]$Actor
        $Row.FlaggedAt = $Now
    }
    $null = Add-CIPPAzDataTableEntity @Table -Entity $Row -Force
    return [string]$Actor
}
