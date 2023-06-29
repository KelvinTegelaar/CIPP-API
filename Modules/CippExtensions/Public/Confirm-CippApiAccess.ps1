function Confirm-CippApiAccess {
    Param(
        $Request,
        $AccessLevel = 'readonly'
    )
    $AuthRequest = [PSCustomObject]@{
        ClientId   = 'None'
        Authorized = $false
    }

    $PermissionMap = @{
        'editor'   = @(
            'editor',
            'readonly'
        )
        'readonly' = @(
            'readonly'
        )
    }

    $Auth = $Request.Headers.authorization
    if ($Auth -match '^Basic (?<Creds>.+)$') {
        try {
            $ClientId, $ClientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Matches.Creds)) -split ':'
            $AuthRequest.ClientId = $ClientId
            $Filter = "PartitionKey eq 'ApiToken' and RowKey eq '{0}' and ClientSecretHash eq '{1}'" -f $ClientId, (Get-ApiSecretHash -Secret $ClientSecret)
            $Table = Get-CippTable -TableName CippApiCredentials
            $Entity = Get-AzDataTableEntity @Table -Filter $Filter

            if ($Entity.RowKey -and $PermissionMap[$Entity.AccessLevel] -contains $AccessLevel) {
                $AuthRequest.Authorized = $true
            }
        } catch {
            Write-Host "API key validation exception: $($_.Exception.Message)"
        }
    }

    if (!$AuthRequest.Authorized) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body       = 'Unauthorized'
            })
    }

    $AuthRequest
}
