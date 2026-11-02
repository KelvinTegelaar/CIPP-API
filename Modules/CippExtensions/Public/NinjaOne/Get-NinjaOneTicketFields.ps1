function Get-NinjaOneTicketFields {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Lists the ticket forms and statuses the NinjaOne ticketing settings can pick from.
    #>
    [CmdletBinding()]
    param()

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne
    $Token = Get-NinjaOneToken -Configuration $Configuration
    $BaseUri = "https://$($Configuration.Instance -replace '/ws', '' -replace 'https://', '')/api/v2/ticketing"
    $Headers = @{ Authorization = "Bearer $($Token.access_token)" }

    $Forms = Invoke-RestMethod -Uri "$BaseUri/ticket-form" -Method GET -Headers $Headers -ContentType 'application/json'
    $Statuses = Invoke-RestMethod -Uri "$BaseUri/statuses" -Method GET -Headers $Headers -ContentType 'application/json'

    # The create call takes the status id as a string, so that is the value stored and sent.
    return @{
        Forms    = @($Forms | Where-Object { $_.active -ne $false } | Select-Object id, name | Sort-Object name)
        Statuses = @($Statuses | ForEach-Object {
                [PSCustomObject]@{
                    statusId    = "$($_.statusId)"
                    name        = $_.name
                    displayName = if ($_.displayName) { $_.displayName } else { $_.name }
                }
            })
    }
}
