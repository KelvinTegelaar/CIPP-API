function New-CippApiKey {
    Param(
        [Parameter(Mandatory = $true)]
        $Description,
        [ValidateSet('readonly', 'editor')]
        $AccessLevel = 'readonly'
    )

    $ClientId = [System.String]([System.Guid]::NewGuid()).Guid
    $ClientSecret = '{0}{1}' -f ([System.Guid]::NewGuid()).Guid, ([System.Guid]::NewGuid()).Guid
    $ClientSecretHash = Get-ApiSecretHash -Secret $ClientSecret

    $ApiAccessObject = [PSCustomObject]@{
        PartitionKey     = 'ApiToken'
        RowKey           = $ClientId
        ClientSecret     = $ClientSecret
        ClientSecretHash = $ClientSecretHash
        Description      = $Description
        AccessLevel      = $AccessLevel
    }

    $Entity = $ApiAccessObject | Select-Object PartitionKey, RowKey, ClientSecretHash, Description, AccessLevel
    $Table = Get-CippTable -TableName 'CippApiCredentials'
    Add-AzDataTableEntity @Table -Force -Entity $Entity

    $ApiAccessObject | Select-Object @{n = 'ClientId'; e = { $_.RowKey } }, ClientSecret, Description, AccessLevel
}
