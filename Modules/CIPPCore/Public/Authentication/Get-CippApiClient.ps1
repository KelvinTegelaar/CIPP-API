function Get-CippApiClient {
    <#
    .SYNOPSIS
        Get the API client details
    .DESCRIPTION
        This function retrieves the API client details
    .PARAMETER AppId
        The AppId of the API client
    .EXAMPLE
        Get-CippApiClient -AppId 'cipp-api'
    #>
    [CmdletBinding()]
    param (
        $AppId
    )

    $Table = Get-CIPPTable -TableName 'ApiClients'
    if ($AppId) {
        $Table.Filter = "RowKey eq '$AppId'"
    }
    $Apps = Get-CIPPAzDataTableEntity @Table | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
    $Apps = foreach ($Client in $Apps) {
        $Client = $Client | Select-Object -Property @{Name = 'ClientId'; Expression = { $_.RowKey } }, AppName, Role, IPRange, Enabled

        if (!$Client.Role) {
            $Client.Role = $null
        }

        if ($Client.IPRange) {
            try {
                $IPRange = @($Client.IPRange | ConvertFrom-Json -ErrorAction Stop)
                if (($IPRange | Measure-Object).Count -eq 0) { @('Any') }
                $Client.IPRange = $IPRange
            } catch {
                $Client.IPRange = @('Any')
            }
        } else {
            $Client.IPRange = @('Any')
        }
        $Client
    }
    return $Apps
}
