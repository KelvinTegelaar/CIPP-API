function Get-CippApiClient {
    <#
    .SYNOPSIS
        Get the API client details
    .DESCRIPTION
        This function retrieves the API client details. A lookup by AppId is read once per invocation: the access
        checks and log lines of one API request all ask for the same client.
    .PARAMETER AppId
        The AppId of the API client
    .EXAMPLE
        Get-CippApiClient -AppId 'cipp-api'
    #>
    [CmdletBinding()]
    param (
        $AppId
    )

    if ($AppId -and $script:CippApiClientMemo -and $script:CippApiClientMemo.ContainsKey("$AppId")) {
        return $script:CippApiClientMemo["$AppId"]
    }

    $Table = Get-CIPPTable -TableName 'ApiClients'
    if ($AppId) {
        $Table.Filter = "RowKey eq '$AppId'"
    }
    $Apps = Get-CIPPAzDataTableEntity @Table | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
    $Apps = foreach ($Client in $Apps) {
        $Client = $Client | Select-Object -Property @{Name = 'ClientId'; Expression = { $_.RowKey } }, AppName, Role, IPRange, @{Name = 'Enabled'; Expression = { "$($_.Enabled)" -eq 'True' } }, @{Name = 'MCPAllowed'; Expression = { [bool]$_.MCPAllowed } }

        if (!$Client.Role) {
            $Client.Role = $null
        }

        if ($Client.IPRange) {
            try {
                $IPRange = @($Client.IPRange | ConvertFrom-Json -ErrorAction Stop)
                if (($IPRange | Measure-Object).Count -eq 0) {
                    $Client.IPRange = @('Any')
                } else {
                    $Client.IPRange = $IPRange
                }
            } catch {
                $Client.IPRange = @('Any')
            }
        } else {
            $Client.IPRange = @('Any')
        }
        $Client
    }
    if ($AppId) {
        $script:CippApiClientMemo ??= @{}
        $script:CippApiClientMemo["$AppId"] = $Apps
    }
    return $Apps
}
